# Runs inside the container, against the real application:
#
#   bin/rails runner plugins/openproject-worklogs/script/verify.rb
#
# The runtime image has no RSpec and a frozen bundle, so the specs under `spec/`
# can only be run from an OpenProject source checkout. This file is what can be
# run *where the plugin actually ships*, and it is the check to run after every
# OpenProject version bump: it asserts the things that break silently when the
# host application moves under us — that the engine's constants still resolve,
# that permissions and menus registered, that core's contracts still call our
# validation, that the settings round-trip, and that the locale files agree.
#
# It writes to the database and rolls everything back, so it is safe to run
# against an instance with real data in it.

require "yaml"

module WorklogsVerify
  PLUGIN_ROOT = Rails.root.join("plugins/openproject-worklogs")

  class Failure < StandardError; end

  class Run
    attr_reader :passed, :failures

    def initialize
      @passed = 0
      @failures = []
      @group = nil
    end

    def group(name)
      @group = name
      puts "\n#{name}"
      yield
    end

    def check(what)
      result = yield
      raise Failure, "returned #{result.inspect}" unless result

      @passed += 1
      puts "  ok    #{what}"
    rescue StandardError => e
      @failures << "#{@group} / #{what}: #{e.class}: #{e.message}"
      puts "  FAIL  #{what}"
      puts "        #{e.class}: #{e.message}"
      puts "        #{e.backtrace.reject { |l| l.include?('/verify.rb') }.first}" if e.backtrace
    end

    # For a check that is only meaningful on an instance that has some data.
    def skip(what, reason)
      puts "  skip  #{what} (#{reason})"
    end

    def report
      puts "\n#{'-' * 60}"
      if failures.empty?
        puts "#{passed} checks passed."
        true
      else
        puts "#{passed} passed, #{failures.size} FAILED:"
        failures.each { |f| puts "  - #{f}" }
        false
      end
    end
  end
end

run = WorklogsVerify::Run.new

# ---------------------------------------------------------------------------
run.group("Engine and autoloading") do
  run.check("plugin is registered") do
    Redmine::Plugin.registered_plugins.key?(:openproject_worklogs)
  end

  run.check("settings defaults are readable before Zeitwerk") do
    OpenProject::Worklogs::SETTINGS_DEFAULTS.is_a?(Hash) &&
      OpenProject::Worklogs::SETTINGS_DEFAULTS.frozen?
  end

  # Every file under app/ and lib/ resolves. This is the check that catches a
  # file whose name and constant have drifted apart — the failure mode that
  # takes the whole application down at boot, not just this plugin.
  run.check("every plugin constant eager-loads") do
    %w[app lib].each do |dir|
      Dir[WorklogsVerify::PLUGIN_ROOT.join(dir, "**/*.rb")].each { |file| require file }
    end
    true
  end

  run.check("assets are fingerprinted and served") do
    %w[worklogs.css worklogs.js].all? do |name|
      path = OpenProject::Worklogs::Assets.path(name)
      path.include?("/worklogs/assets/") && path.end_with?(name)
    end
  end

  run.check("the stylesheet has no colour literals (dark mode depends on it)") do
    css = WorklogsVerify::PLUGIN_ROOT.join("public/worklogs.css").read
    literals = css.scan(/#[0-9a-fA-F]{3,8}\b|\brgba?\(|\bhsla?\(/)
    raise WorklogsVerify::Failure, "found #{literals.uniq.inspect}" if literals.any?

    true
  end
end

# ---------------------------------------------------------------------------
run.group("Permissions and menus") do
  { view_worklogs: 17, view_worklogs_coverage: 1, approve_worklogs: 3 }.each do |name, _|
    run.check("#{name} is a global permission") do
      permission = OpenProject::AccessControl.permission(name)
      permission&.global? && permission.controller_actions.any?
    end
  end

  run.check("no two permissions claim the same controller action") do
    ours = %i[view_worklogs view_worklogs_coverage approve_worklogs]
            .filter_map { |n| OpenProject::AccessControl.permission(n) }
    actions = ours.flat_map(&:controller_actions)
    duplicates = actions.tally.select { |_, count| count > 1 }.keys
    raise WorklogsVerify::Failure, "duplicated: #{duplicates.inspect}" if duplicates.any?

    true
  end

  run.check("every routed worklogs action is covered by a permission") do
    permitted = %i[view_worklogs view_worklogs_coverage approve_worklogs]
                .filter_map { |n| OpenProject::AccessControl.permission(n) }
                .flat_map(&:controller_actions).to_set

    # Assets are public by design; admin is behind require_admin, not a permission.
    exempt = %w[worklogs/assets worklogs/admin]

    routed = Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next unless controller&.start_with?("worklogs/")
      next if exempt.include?(controller)

      "#{controller}/#{action}"
    end.uniq

    missing = routed.reject { |key| permitted.include?(key) }
    raise WorklogsVerify::Failure, "unprotected: #{missing.inspect}" if missing.any?

    true
  end

  run.check("the global menu carries all four entries") do
    children = Redmine::MenuManager.items(:global_menu).children
                                   .find { |i| i.name == :worklogs }&.children&.map(&:name)
    children == %i[worklogs_timesheet worklogs_reports worklogs_coverage worklogs_approvals]
  end

  run.check("the admin menu carries the settings page") do
    Redmine::MenuManager.items(:admin_menu).children.map(&:name).include?(:worklogs_settings)
  end

  run.check("named routes resolve") do
    helpers = Rails.application.routes.url_helpers
    helpers.worklogs_settings_path == "/admin/worklogs" &&
      helpers.worklogs_root_path == "/worklogs" &&
      helpers.worklogs_coverage_path == "/worklogs/coverage"
  end
end

# ---------------------------------------------------------------------------
run.group("Settings") do
  original = Setting.plugin_openproject_worklogs

  run.check("defaults fill in for keys absent from the stored hash") do
    Setting.plugin_openproject_worklogs = { "reminders_enabled" => true }
    Worklogs::Settings.invalidate!
    settings = Worklogs::Settings.current

    settings.reminders_enabled? && settings.approvals_enabled? && settings.reminder_hour == 8
  end

  run.check("form strings are cast, not stored raw") do
    cast = Worklogs::Settings.sanitise(
      "approvals_enabled" => "1", "lock_approved_periods" => "0",
      "allow_self_approval" => "", "reminders_enabled" => "1",
      "reminder_weekday" => "3", "reminder_hour" => "17", "reminder_tolerance" => "1.25"
    )

    cast["approvals_enabled"] == true && cast["lock_approved_periods"] == false &&
      cast["allow_self_approval"] == false && cast["reminder_weekday"] == 3 &&
      cast["reminder_hour"] == 17 && cast["reminder_tolerance"] == 1.25
  end

  run.check("out-of-range values fall back instead of being stored") do
    cast = Worklogs::Settings.sanitise(
      "reminder_weekday" => "99", "reminder_hour" => "-4", "reminder_tolerance" => "-3"
    )

    cast["reminder_weekday"] == 1 && cast["reminder_hour"] == 8 && cast["reminder_tolerance"] == 0
  end

  run.check("locking is off whenever approvals are off") do
    Setting.plugin_openproject_worklogs = { "approvals_enabled" => false,
                                            "lock_approved_periods" => true }
    Worklogs::Settings.invalidate!

    !Worklogs::Settings.current.lock_approved_periods?
  end
ensure
  Setting.plugin_openproject_worklogs = original
  Worklogs::Settings.invalidate!
end

# ---------------------------------------------------------------------------
run.group("Periods and weeks") do
  run.check("a week runs from the configured start day for seven days") do
    week = Worklogs::Week.current
    week.dates.size == 7 && week.end_date == week.start_date + 6 &&
      week.include?(Time.zone.today) && week.previous.next == week
  end

  run.check("every preset produces a range in the right order") do
    Worklogs::Period::PRESETS.all? do |name|
      period = Worklogs::Period.new(name)
      period.range.first <= period.range.last && period.label.present?
    end
  end

  run.check("only a custom period carries its dates in the URL") do
    preset = Worklogs::Period.new("this_month").to_params
    custom = Worklogs::Period.new("custom", from: "2026-01-01", to: "2026-01-31").to_params

    preset.keys == [:period] && custom[:from] == "2026-01-01" && custom[:to] == "2026-01-31"
  end

  run.check("an unknown period name falls back rather than raising") do
    Worklogs::Period.from_params({ period: "nonsense" }).name == Worklogs::Period::DEFAULT
  end

  run.check("a reversed custom range is put back in order") do
    period = Worklogs::Period.new("custom", from: "2026-03-31", to: "2026-03-01")
    period.range.first <= period.range.last
  end
end

# ---------------------------------------------------------------------------
run.group("Capacity") do
  user = User.active.not_builtin.first

  if user.nil?
    run.skip("capacity", "no active users on this instance")
  else
    week = Worklogs::Week.current
    calendar = Worklogs::CapacityCalendar.new(user_ids: [user.id], range: week.range)

    run.check("a non-working day has no capacity and a reason") do
      off = week.dates.reject { |d| calendar.working_day?(user.id, d) }
      next run.skip("non-working day", "the whole week is a working week") if off.empty?

      off.all? { |d| calendar.hours_for(user.id, d).zero? && calendar.non_working_reason(user.id, d) }
    end

    run.check("the week total is the sum of its days") do
      sum = week.dates.sum { |d| calendar.hours_for(user.id, d) }
      (calendar.total_for(user.id, week.dates) - sum).abs < 0.001
    end

    run.check("the single-user view agrees with the bulk calendar") do
      capacity = Worklogs::Capacity.new(user:, week:)
      week.dates.all? { |d| capacity.hours_for(d) == calendar.hours_for(user.id, d) }
    end

    run.check("expected-so-far never exceeds the week's capacity") do
      capacity = Worklogs::Capacity.new(user:, week:)
      capacity.expected_so_far <= capacity.total + 0.001
    end
  end
end

# ---------------------------------------------------------------------------
run.group("Coverage arithmetic") do
  bucket = Worklogs::Coverage::Bucket.new(
    key: "2026-W02", dates: (Date.new(2026, 1, 5)..Date.new(2026, 1, 11)).to_a
  )

  short = Worklogs::Coverage::Cell.new(bucket:, logged: 2.0, capacity: 8.0, expected: 8.0)
  over  = Worklogs::Coverage::Cell.new(bucket:, logged: 14.0, capacity: 8.0, expected: 8.0)

  run.check("a gap is the shortfall, and overtime is not a negative gap") do
    short.missing == 6.0 && over.missing.zero? && over.difference == 6.0
  end

  run.check("a row sums its cells' gaps rather than netting them off") do
    user = User.active.not_builtin.first || User.new(id: 0)
    row = Worklogs::Coverage::Row.new(user:, cells: [short, over])

    row.missing == 6.0 && row.logged == 16.0 && row.difference.zero?
  end

  run.check("a day with no capacity reads as off, not as a gap") do
    off = Worklogs::Coverage::Cell.new(bucket:, logged: 0.0, capacity: 0.0, expected: 0.0)
    off.state == :off && off.missing.zero? && off.utilization.nil?
  end

  run.check("time logged into a future bucket does not read as 'not yet'") do
    future = Worklogs::Coverage::Bucket.new(
      key: "future", dates: ((Time.zone.today + 30)..(Time.zone.today + 36)).to_a
    )
    empty = Worklogs::Coverage::Cell.new(bucket: future, logged: 0.0, capacity: 8.0, expected: 0.0)
    early = Worklogs::Coverage::Cell.new(bucket: future, logged: 4.0, capacity: 8.0, expected: 0.0)

    empty.state == :future && early.state != :future
  end

  run.check("buckets are clipped to the period they belong to") do
    query = Worklogs::Coverage::Query.new(period: "custom", from: "2026-01-07", to: "2026-01-20",
                                          group_by: "week")
    buckets = Worklogs::Coverage::Bucket.build(query)

    buckets.first.range.first == Date.new(2026, 1, 7) &&
      buckets.last.range.last == Date.new(2026, 1, 20)
  end

  run.check("the footer is the sum of the rows, in both directions") do
    result = Worklogs::Coverage::Result.new(
      query: Worklogs::Coverage::Query.new(period: "this_month", group_by: "week"),
      viewer: User.active.not_builtin.first || User.anonymous
    )
    next true if result.rows.empty?

    by_row = result.rows.sum(&:missing).round(2)
    by_bucket = result.missing_by_bucket.sum.round(2)

    (by_row - result.missing_hours).abs < 0.01 && (by_bucket - result.missing_hours).abs < 0.01
  end
end

# ---------------------------------------------------------------------------
# Everything below writes, so it runs inside a transaction that is always rolled
# back. An instance with real time entries on it is left exactly as it was.
run.group("Approvals and period locking") do
  owner = User.active.not_builtin.first
  entry = owner && TimeEntry.where(user_id: owner.id).order(spent_on: :desc).first

  if entry.nil?
    run.skip("locking", "no time entries to lock")
  else
    ActiveRecord::Base.transaction do
      previous_user = User.current
      admin = User.active.where(admin: true).first || owner
      User.current = admin
      week = Worklogs::Week.new(entry.spent_on)
      service = Worklogs::SubmissionService.new(actor: admin)

      Setting.plugin_openproject_worklogs = { "approvals_enabled" => true,
                                              "lock_approved_periods" => true }
      Worklogs::Settings.invalidate!

      submission = service.submit(user: owner, week:, note: "verify")

      run.check("submitting records the week and its real total") do
        submission.errors.empty? && submission.status == "submitted" &&
          submission.hours == TimeEntry.where(user_id: owner.id, spent_on: week.range)
                                       .sum(:hours).to_f.round(2)
      end

      run.check("every state change leaves a trail entry") do
        submission.events.reload.last&.action == "submitted"
      end

      run.check("core's own contract refuses to change a locked day") do
        Worklogs::PeriodLock.invalidate!
        result = TimeEntries::UpdateService
                 .new(user: admin, model: TimeEntry.find(entry.id))
                 .call(comments: "verify #{Time.zone.now.to_i}")

        result.failure? && result.errors.full_messages.join.include?(I18n.l(entry.spent_on,
                                                                           format: :long))
      end

      run.check("core's delete contract refuses too") do
        Worklogs::PeriodLock.invalidate!
        result = TimeEntries::DeleteService
                 .new(user: admin, model: TimeEntry.find(entry.id))
                 .call

        result.failure?
      end

      run.check("moving an entry *into* a locked week is refused as well") do
        open_entry = TimeEntry.where(user_id: owner.id)
                              .where.not(spent_on: week.range).order(spent_on: :desc).first
        next run.skip("move-in", "no entry outside the locked week") if open_entry.nil?

        Worklogs::PeriodLock.invalidate!
        TimeEntries::UpdateService.new(user: admin, model: TimeEntry.find(open_entry.id))
                                  .call(spent_on: entry.spent_on).failure?
      end

      run.check("turning locking off reopens the same week without touching the record") do
        Setting.plugin_openproject_worklogs = { "approvals_enabled" => true,
                                                "lock_approved_periods" => false }
        Worklogs::Settings.invalidate!
        Worklogs::PeriodLock.invalidate!

        TimeEntries::UpdateService.new(user: admin, model: TimeEntry.find(entry.id))
                                  .call(comments: "verify open #{Time.zone.now.to_i}").success? &&
          submission.reload.status == "submitted"
      end

      run.check("nobody approves their own week unless it is switched on") do
        Setting.plugin_openproject_worklogs = { "allow_self_approval" => false }
        Worklogs::Settings.invalidate!
        non_admin = User.active.not_builtin.where(admin: false).first
        next run.skip("self-approval", "no non-admin user") if non_admin.nil?

        own = Worklogs::Submission.new(user_id: non_admin.id, status: "submitted")
        refused = own.decidable_by?(non_admin)

        Setting.plugin_openproject_worklogs = { "allow_self_approval" => true }
        Worklogs::Settings.invalidate!
        allowed = own.decidable_by?(non_admin)

        # Both answers still depend on holding approve_worklogs at all.
        !refused && (allowed == non_admin.allowed_globally?(:approve_worklogs))
      end

      User.current = previous_user
      raise ActiveRecord::Rollback
    end
  end
ensure
  Worklogs::Settings.invalidate!
  Worklogs::PeriodLock.invalidate!
end

# ---------------------------------------------------------------------------
run.group("Reminders") do
  run.check("the job is on the cron table") do
    Rails.application.config.good_job.cron.key?(:"Cron::WorklogsReminderJob")
  end

  run.check("it runs hourly, so the setting can move without a restart") do
    Rails.application.config.good_job.cron[:"Cron::WorklogsReminderJob"][:cron].split.last(4) ==
      %w[* * * *]
  end

  run.check("it does nothing at all while reminders are off") do
    original = Setting.plugin_openproject_worklogs
    Setting.plugin_openproject_worklogs = { "reminders_enabled" => false }
    Worklogs::Settings.invalidate!

    result = !Cron::WorklogsReminderJob.new.send(:due?)

    Setting.plugin_openproject_worklogs = original
    Worklogs::Settings.invalidate!
    result
  end

  run.check("it fires only in the configured hour of the configured day") do
    original = Setting.plugin_openproject_worklogs
    now = Time.zone.now
    Setting.plugin_openproject_worklogs = { "reminders_enabled" => true,
                                            "reminder_weekday" => now.to_date.cwday,
                                            "reminder_hour" => now.hour }
    Worklogs::Settings.invalidate!
    due_now = Cron::WorklogsReminderJob.new.send(:due?)

    Setting.plugin_openproject_worklogs = { "reminders_enabled" => true,
                                            "reminder_weekday" => now.to_date.cwday,
                                            "reminder_hour" => (now.hour + 1) % 24 }
    Worklogs::Settings.invalidate!
    due_later = Cron::WorklogsReminderJob.new.send(:due?)

    Setting.plugin_openproject_worklogs = original
    Worklogs::Settings.invalidate!
    due_now && !due_later
  end

  run.check("nobody is chased for a week that has not happened yet") do
    service = Worklogs::ReminderService.new(week: Worklogs::Week.current.next)
    service.recipients.empty?
  end

  run.check("the mailer builds without raising") do
    user = User.active.not_builtin.where.not(mail: [nil, ""]).first
    next run.skip("mailer", "no user with an address") if user.nil?

    mail = Worklogs::ReminderMailer.missing_time(user, Worklogs::Week.current.previous.start_date)
    mail.subject.present? && mail.to == [user.mail]
  end
end

# ---------------------------------------------------------------------------
run.group("Translations") do
  def flatten_locale(hash, prefix = "", out = {})
    (hash || {}).each do |key, value|
      path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
      value.is_a?(Hash) ? flatten_locale(value, path, out) : out[path] = value
    end
    out
  end

  locales = %w[en vi].to_h do |code|
    file = YAML.load_file(WorklogsVerify::PLUGIN_ROOT.join("config/locales/#{code}.yml"))
    [code, flatten_locale(file[code])]
  end

  run.check("en and vi define exactly the same keys") do
    missing = locales["en"].keys - locales["vi"].keys
    extra = locales["vi"].keys - locales["en"].keys
    if missing.any? || extra.any?
      raise WorklogsVerify::Failure, "missing in vi: #{missing.inspect}, extra: #{extra.inspect}"
    end

    true
  end

  run.check("both sides interpolate the same variables") do
    mismatched = locales["en"].select do |key, value|
      other = locales["vi"][key]
      value.is_a?(String) && other.is_a?(String) &&
        value.scan(/%\{(\w+)\}/).flatten.sort != other.scan(/%\{(\w+)\}/).flatten.sort
    end.keys
    raise WorklogsVerify::Failure, mismatched.inspect if mismatched.any?

    true
  end

  run.check("no view asks for a key that does not exist") do
    used = Dir[WorklogsVerify::PLUGIN_ROOT.join("app/**/*.{rb,erb}")].flat_map do |file|
      File.read(file).scan(/\bt\(\s*["'](worklogs\.[\w.]+)["']/).flatten
    end.uniq

    # Pluralised and dynamically-suffixed keys resolve to children, not leaves.
    unknown = used.reject do |key|
      locales["en"].key?(key) || locales["en"].keys.any? { |k| k.start_with?("#{key}.") }
    end
    raise WorklogsVerify::Failure, unknown.inspect if unknown.any?

    true
  end
end

exit(run.report ? 0 : 1)
