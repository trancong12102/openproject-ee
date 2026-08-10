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
require "csv"

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

  run.check("the global menu carries all five entries, in reading order") do
    children = Redmine::MenuManager.items(:global_menu).children
                                   .find { |i| i.name == :worklogs }&.children&.map(&:name)
    children == %i[worklogs_timesheet worklogs_team worklogs_reports worklogs_coverage
                   worklogs_approvals]
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

  # The whole reason this setting exists: core's hours_per_day is an integer,
  # so a seven-and-a-half-hour day cannot be said there at all.
  run.check("a fractional day survives the form, and a blank one means \"follow core\"") do
    cast = Worklogs::Settings.sanitise("hours_per_day" => "7.5")
    blank = Worklogs::Settings.sanitise("hours_per_day" => "")
    silly = Worklogs::Settings.sanitise("hours_per_day" => "40")

    cast["hours_per_day"] == 7.5 && blank["hours_per_day"].nil? && silly["hours_per_day"] == 24
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

  # The arrows either side of the period chip. A preset can only be stepped by
  # resolving it to the anchored period it names, so this is the check that
  # says the arrows keep working past the first click.
  run.check("a preset steps into the anchored period it names") do
    stepped = Worklogs::Period.new("this_month").previous
    twice = stepped.previous

    stepped.name == "month" && stepped.from == Time.zone.today.last_month.beginning_of_month &&
      twice.from == (Time.zone.today.last_month.beginning_of_month << 1) && twice.name == "month"
  end

  run.check("every anchored period survives the round trip through its URL") do
    Worklogs::Period::ANCHORED.all? do |unit|
      period = Worklogs::Period.anchored(unit, Date.new(2026, 5, 14))

      Worklogs::Period.from_params(period.to_params) == period &&
        period.to_params.keys.sort == %i[from period] && period.label.present?
    end
  end

  run.check("a month picker's YYYY-MM is understood") do
    period = Worklogs::Period.new("month", from: "2026-02")

    period.from == Date.new(2026, 2, 1) && period.to == Date.new(2026, 2, 28)
  end

  # A range with no unit still has a width, and stepping it by anything else
  # would silently change how much it covers.
  run.check("a period with no unit steps by its own length") do
    period = Worklogs::Period.new("last_30_days").previous

    period.custom? && period.length == 30 && period.to == Time.zone.today - 30
  end

  run.check("stepping never leaves the old dates behind") do
    query = Worklogs::Reports::Query.from_params({ period: "custom", from: "2026-01-01", to: "2026-01-31" })
    stepped = query.with_period(Worklogs::Period.anchored("month", Date.new(2026, 6, 3)))

    stepped.to_params[:period] == "month" && stepped.to_params[:from] == "2026-06-01" &&
      !stepped.to_params.key?(:to) && stepped.from == Date.new(2026, 6, 1)
  end
end

# ---------------------------------------------------------------------------
run.group("Spans") do
  run.check("a month covers its own days and nothing else") do
    month = Worklogs::Month.containing(Date.new(2026, 2, 14))

    month.dates.size == 28 && month.start_date == Date.new(2026, 2, 1) &&
      month.end_date == Date.new(2026, 2, 28) && month.previous.next == month
  end

  # The weeks at either end of a month belong to it too: a submission covers a
  # whole week, and a month that ignored the spill would be silent about the
  # first and last few days it is showing.
  run.check("a month lists every week that touches it") do
    month = Worklogs::Month.containing(Date.new(2026, 8, 10))
    weeks = month.weeks

    weeks.first.include?(month.start_date) && weeks.last.include?(month.end_date) &&
      weeks.each_cons(2).all? { |a, b| a.next == b }
  end

  run.check("a week is its own only week, so both spans answer the same questions") do
    week = Worklogs::Week.current

    week.weeks == [week] && week.kind == "week" && week.week? && !week.month? &&
      week.to_params == { date: week.to_param }
  end

  run.check("an unrecognised span is a week rather than an error") do
    Worklogs::Span.from_params({ span: "fortnight", date: "nonsense" }).is_a?(Worklogs::Week) &&
      Worklogs::Span.from_params({}).is_a?(Worklogs::Week)
  end

  run.check("switching span keeps you where you were standing") do
    week = Worklogs::Week.containing(Date.new(2026, 3, 18))
    month = Worklogs::Span.switch(week, "month")

    month.is_a?(Worklogs::Month) && month.start_date == Date.new(2026, 3, 1) &&
      Worklogs::Span.switch(month, "week").is_a?(Worklogs::Week) &&
      Worklogs::Span.switch(week, "week") == week
  end

  run.check("a month carries its span in the URL and a week does not") do
    Worklogs::Month.current.to_params[:span] == "month" &&
      !Worklogs::Week.current.to_params.key?(:span)
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

    # A per-user schedule still wins; this is only about everybody else.
    run.check("without a schedule of their own, a day is worth what the setting says") do
      if UserWorkingHours.where(user_id: user.id).exists?
        next run.skip("plugin hours_per_day", "this user keeps working hours of their own")
      end

      original = Setting.plugin_openproject_worklogs
      begin
        Setting.plugin_openproject_worklogs =
          Worklogs::Settings.sanitise(Worklogs::Settings.raw.merge("hours_per_day" => "7.5"))
        Worklogs::Settings.invalidate!

        fresh = Worklogs::CapacityCalendar.new(user_ids: [user.id], range: week.range)
        working = week.dates.find { |date| fresh.working_day?(user.id, date) }

        working.nil? || fresh.hours_for(user.id, working) == 7.5
      ensure
        Setting.plugin_openproject_worklogs = original
        Worklogs::Settings.invalidate!
      end
    end

    run.check("the week total is the sum of its days") do
      sum = week.dates.sum { |d| calendar.hours_for(user.id, d) }
      (calendar.total_for(user.id, week.dates) - sum).abs < 0.001
    end

    run.check("the single-user view agrees with the bulk calendar") do
      capacity = Worklogs::Capacity.new(user:, span: week)
      week.dates.all? { |d| capacity.hours_for(d) == calendar.hours_for(user.id, d) }
    end

    run.check("expected-so-far never exceeds the week's capacity") do
      capacity = Worklogs::Capacity.new(user:, span: week)
      capacity.expected_so_far <= capacity.total + 0.001
    end

    # The same object, asked about more days. If capacity had a week baked into
    # it anywhere, this is where it would show.
    run.check("a month's capacity is the sum of the weeks inside it") do
      month = Worklogs::Month.current
      whole = Worklogs::Capacity.new(user:, span: month).total
      by_day = month.dates.sum { |date| Worklogs::Capacity.new(user:, span: month).hours_for(date) }

      (whole - by_day).abs < 0.001 && whole >= Worklogs::Capacity.new(user:, span: week).total
    end
  end
end

# ---------------------------------------------------------------------------
run.group("Timesheets") do
  user = User.active.not_builtin.first

  if user.nil?
    run.skip("timesheets", "no active users on this instance")
  else
    month = Worklogs::Month.current

    run.check("a month sheet draws a column for every day of the month") do
      sheet = Worklogs::Timesheet.new(user:, span: month, viewer: user)

      sheet.dates == month.dates && sheet.dates.size.between?(28, 31)
    end

    run.check("the sheet's total is the sum of its days") do
      sheet = Worklogs::Timesheet.new(user:, span: month, viewer: user)
      summed = sheet.dates.sum { |date| sheet.daily_total(date) }

      (sheet.total - summed).abs < 0.001
    end

    # A filter that filters nothing is a filter that lies about what is on
    # screen; one that filters everything must leave the sheet honestly empty.
    run.check("a project filter narrows the sheet and never widens it") do
      all = Worklogs::Timesheet.new(user:, span: month, viewer: user)
      next run.skip("project filter", "nothing logged this month") if all.empty?

      project_id = all.rows.filter_map { |row| row.project&.id }.first
      kept = Worklogs::Timesheet.new(user:, span: month, viewer: user, project_ids: [project_id])
      none = Worklogs::Timesheet.new(user:, span: month, viewer: user, project_ids: [-1])

      kept.rows.size <= all.rows.size && kept.total <= all.total + 0.001 &&
        kept.rows.all? { |row| row.project&.id == project_id } &&
        none.empty? && none.filtered? && none.filter_count == 1
    end

    run.check("an unfiltered sheet does not claim to be filtered") do
      sheet = Worklogs::Timesheet.new(user:, span: month, viewer: user)

      !sheet.filtered? && sheet.filter_count.zero?
    end

    # The one thing a month view could get badly wrong: locking the whole month
    # because one week of it was signed off.
    run.check("a month locks the week that was submitted and no other") do
      locked = nil

      ActiveRecord::Base.transaction do
        week = month.weeks[1]
        Worklogs::SubmissionService.new(actor: user).submit(user:, week:)
        Worklogs::PeriodLock.invalidate!

        sheet = Worklogs::Timesheet.new(user:, span: month, viewer: user)
        other = month.weeks.find { |candidate| candidate != week }

        locked = sheet.locked_on?(week.start_date) && !sheet.locked_on?(other.start_date) &&
                 sheet.any_locked? && !sheet.locked? && sheet.submission.nil?

        raise ActiveRecord::Rollback
      end

      Worklogs::PeriodLock.invalidate!
      locked
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
run.group("Report filters") do
  viewer = User.active.not_builtin.first || User.anonymous
  base = Worklogs::Reports::Query.from_params({ period: "this_year" })
  count = ->(query) { Worklogs::Reports::Scope.new(query:, viewer:).relation.count }

  run.check("every filter has a reader, a URL name and a label") do
    Worklogs::Reports::Query::FILTERS.all? do |name|
      base.respond_to?(:"#{name}_ids") && base.selected_ids(name) == [] &&
        I18n.exists?("worklogs.reports.dimensions.#{name == :work_package ? 'entity' : name}")
    end
  end

  run.check("filters survive the round trip into a saved report and back") do
    definition = base.merge(assignee_ids: [0], priority_ids: [1], version_ids: [2],
                            work_package_ids: [3], text: "invoice").definition_params

    Worklogs::Reports::Query.from_params(definition).definition_params == definition
  end

  run.check("the text filter counts as a filter") do
    query = base.merge(text: "invoice")

    query.filters? && query.filter_count == 1 && base.filter_count.zero?
  end

  # A search box that let its input reach SQL as syntax would turn "%" into
  # "everything" — the one input where a user cannot tell they are being lied to.
  run.check("a wildcard in the search box is a character, not a wildcard") do
    everything = count.call(base)
    next run.skip("search escaping", "nothing logged this year") if everything.zero?

    count.call(base.merge(text: "%")) < everything
  end

  run.check("the work package filter never matches time logged elsewhere") do
    entry = TimeEntry.where(entity_type: "WorkPackage").first
    next run.skip("work package filter", "no time logged on a work package") if entry.nil?

    filtered = Worklogs::Reports::Scope.new(query: base.merge(work_package_ids: [entry.entity_id]), viewer:)
                                       .relation

    filtered.all? { |row| row.entity_type == "WorkPackage" && row.entity_id == entry.entity_id }
  end

  # "Nobody" has to mean a work package with no assignee, not a time entry with
  # no work package: the left join leaves a meeting's assignee null too.
  run.check("unassigned means unassigned, not un-work-packaged") do
    scope = Worklogs::Reports::Scope.new(query: base.merge(assignee_ids: [Worklogs::Reports::Scope::UNASSIGNED]),
                                         viewer:).relation

    scope.all? { |row| row.entity_type == "WorkPackage" }
  end

  run.check("the new dimensions group and resolve") do
    %w[assignee priority version].all? do |key|
      dimension = Worklogs::Reports::Dimension.find(key)

      dimension&.requires_work_package_join? && dimension.expression.start_with?("work_packages.") &&
        dimension.resolve([]).empty? && dimension.label.present?
    end
  end
end

run.group("Team sheet") do
  viewer = User.active.not_builtin.first || User.anonymous
  span = Worklogs::Week.current
  base = Worklogs::Team::Query.from_params({ date: span.to_param })
  sheet = ->(query) { Worklogs::Team::Sheet.new(query:, viewer:) }

  run.check("the page is its URL, defaults left out of it") do
    base.to_params == { date: span.to_param } &&
      base.merge(scope: "everyone", sort: "hours").to_params[:scope] == "everyone" &&
      Worklogs::Team::Query.from_params(base.to_params).to_params == base.to_params
  end

  run.check("a span replaces a span whole, dates included") do
    month = base.with_span(Worklogs::Month.containing(Date.new(2026, 8, 14)))

    month.span.is_a?(Worklogs::Month) && month.to_params[:span] == "month" &&
      month.with_span(Worklogs::Week.current).to_params[:span].nil?
  end

  # Expansion rides in the URL like every other control, so it survives the back
  # button and can be sent to somebody as a link.
  run.check("opening a person up is a link, and toggles back off") do
    user = User.active.not_builtin.first
    next run.skip("expansion", "no users") if user.nil?

    opened = base.toggling(user)

    opened.expanded?(user) && opened.to_params[:expand] == [user.id] &&
      !opened.toggling(user).expanded?(user)
  end

  run.check("at most a handful of people can be opened at once") do
    Worklogs::Team::Query.from_params({ expand: (1..20).to_a }).expanded_ids.size ==
      Worklogs::Team::Query::MAX_EXPANDED
  end

  run.check("a person's line adds up to their days") do
    row = sheet.call(base.merge(scope: "everyone")).rows.first
    next run.skip("row arithmetic", "nobody to show") if row.nil?

    row.logged == span.dates.sum { |date| row.on(date) }.round(2)
  end

  # The balance is measured against what was owed *by today*: a table that calls
  # everybody 32 hours short every Monday is a table nobody opens twice.
  run.check("the balance is owed-so-far, never the whole span") do
    row = sheet.call(base.merge(scope: "everyone")).rows.first
    next run.skip("balance", "nobody to show") if row.nil?

    row.expected <= row.capacity && row.difference == (row.logged - row.expected).round(2)
  end

  run.check("the default list is the people with time on it") do
    everyone = sheet.call(base.merge(scope: "everyone"))
    logged = sheet.call(base)
    next run.skip("scope", "nobody logged anything this week") if logged.rows.empty?

    logged.rows.all?(&:logged?) && logged.rows.size <= everyone.rows.size &&
      logged.logged_count == everyone.logged_count
  end

  run.check("ordering by hours is stable, and by name is the default") do
    ordered = sheet.call(base.merge(scope: "everyone", sort: "hours")).rows
    named = sheet.call(base.merge(scope: "everyone")).rows

    ordered.map(&:logged) == ordered.map(&:logged).sort.reverse &&
      named.map(&:sort_key) == named.map(&:sort_key).sort
  end

  # A day nobody was asked to work is not a day anybody is missing.
  run.check("a gap is an empty working day that has already happened") do
    row = sheet.call(base.merge(scope: "everyone")).rows.first
    next run.skip("gaps", "nobody to show") if row.nil?

    span.dates.none? { |date| row.gap?(date) && (row.off?(date) || date > Time.zone.today) }
  end

  run.check("the sheet cannot be widened past what the viewer may see in core") do
    source = Worklogs::Team::Sheet.instance_method(:logged).source_location
    body = File.read(source.first).lines[(source.last - 1)..(source.last + 6)].join

    body.include?("TimeEntry.visible(viewer)")
  end

  run.check("the export writes numbers, and says what it left out") do
    csv = Worklogs::Team::CsvExport.new(sheet: sheet.call(base.merge(scope: "everyone"))).to_csv
    header = CSV.parse_line(csv)

    header.first == I18n.t("worklogs.reports.dimensions.user") &&
      header.include?(span.start_date.iso8601) &&
      csv.include?(I18n.t("worklogs.team.export_note"))
  end
end

# The .xlsx writer is this plugin's own, so nothing else is going to notice when
# it emits a file no spreadsheet will open. These checks are that noticing.
run.group("Workbooks") do
  require "zip"

  viewer = User.active.not_builtin.first || User.anonymous
  # `open_buffer` hands back the buffer, not the block's value.
  parts = lambda do |data|
    entries = nil
    Zip::File.open_buffer(data) { |zip| entries = zip.entries.to_h { |e| [e.name, zip.read(e.name)] } }
    entries
  end

  workbook = Worklogs::Xlsx::Workbook.new do |book|
    book.sheet("Hours") do |sheet|
      sheet.format_columns(:hours, from: 1)
      sheet.title("Title")
      sheet.header(%w[Who Hours])
      sheet.row(["Ann & <Bob>", 7.5])
      sheet.total(["Total", 7.5])
    end
  end
  files = parts.call(workbook.to_xlsx)

  run.check("a workbook is a zip carrying every part a reader opens") do
    %w[[Content_Types].xml _rels/.rels xl/workbook.xml xl/_rels/workbook.xml.rels
       xl/styles.xml xl/worksheets/sheet1.xml].all? { |name| files.key?(name) }
  end

  run.check("every part parses as XML") do
    files.values.all? { |content| Nokogiri::XML(content) { |config| config.strict }.errors.empty? }
  end

  # The whole point of the format over a CSV: a figure Excel will re-sum.
  run.check("figures go out as numbers, text goes out as text") do
    sheet = Nokogiri::XML(files["xl/worksheets/sheet1.xml"])
    hours = sheet.at_css(%(c[r="B3"]))
    who = sheet.at_css(%(c[r="A3"]))

    hours.at_css("v")&.text == "7.5" && hours["t"].nil? &&
      who["t"] == "inlineStr" && who.at_css("t").text == "Ann & <Bob>"
  end

  run.check("a number carries the format of its column, a word does not") do
    sheet = Nokogiri::XML(files["xl/worksheets/sheet1.xml"])
    cells = sheet.css("c").to_h { |cell| [cell["r"], cell["s"].to_i] }

    cells["B3"] == Worklogs::Xlsx::Styles::DECIMAL &&
      cells["B4"] == Worklogs::Xlsx::Styles::BOLD_DECIMAL &&
      cells["A3"] == Worklogs::Xlsx::Styles::DEFAULT
  end

  run.check("the style table declares every style a cell can ask for") do
    declared = Nokogiri::XML(files["xl/styles.xml"]).css("cellXfs xf").size
    used = Worklogs::Xlsx::Styles.constants.filter_map do |name|
      value = Worklogs::Xlsx::Styles.const_get(name)
      value if value.is_a?(Integer) && name != :CURRENCY_FORMAT_ID
    end

    used.max < declared && declared == 8
  end

  # An attribute closed early by a quote is a file that will not open at all,
  # and the currency sign arrives inside quotes by design.
  run.check("a currency sign cannot break out of an attribute") do
    escaped = Worklogs::Xlsx::Cell.escape_attribute(%(#,##0.00 "€"))

    !escaped.include?('"') && escaped.include?("&quot;") &&
      Nokogiri::XML(%(<a b="#{escaped}"/>)) { |config| config.strict }.errors.empty?
  end

  run.check("the header freezes itself in place") do
    files["xl/worksheets/sheet1.xml"].include?(%(state="frozen"))
  end

  # Excel refuses the whole file rather than telling you the tab is misnamed.
  run.check("a sheet name Excel would refuse is made safe") do
    sheet = Worklogs::Xlsx::Sheet.new("Report: 2026/08 [draft] with a very long tail indeed")

    sheet.name.length <= 31 && sheet.name !~ %r{[\[\]:*?/\\]}
  end

  run.check("column references keep going past Z") do
    names = [0, 25, 26, 27, 51, 52].map { |index| Worklogs::Xlsx::Cell.column_name(index) }

    names == %w[A Z AA AB AZ BA]
  end

  # Free text somebody pasted from a chat window is the likeliest thing here to
  # be unopenable, and it arrives in the comment column of every detail export.
  run.check("a control character in a comment cannot break the file") do
    cell = Worklogs::Xlsx::Cell.new(value: "one\u0000two\u0008three", reference: "A1")

    cell.to_xml.include?("onetwothree") &&
      Nokogiri::XML("<r>#{cell.to_xml}</r>") { |config| config.strict }.errors.empty?
  end

  run.check("the registered type is the one the writer says it writes") do
    Mime[:xlsx]&.to_s == Worklogs::Xlsx::Workbook::CONTENT_TYPE
  end

  # Four pages, one writer. A format that only works on the page it was written
  # for is a format that breaks on the other three without anybody noticing.
  run.check("every page that offers a workbook can build one") do
    team = Worklogs::Team::Sheet.new(query: Worklogs::Team::Query.from_params({}), viewer:)
    coverage = Worklogs::Coverage::Result.new(query: Worklogs::Coverage::Query.from_params({}), viewer:)
    report = Worklogs::Reports::Result.new(query: Worklogs::Reports::Query.from_params({}), viewer:)

    [Worklogs::Team::XlsxExport.new(sheet: team).to_xlsx,
     Worklogs::Coverage::XlsxExport.new(result: coverage).to_xlsx,
     Worklogs::Reports::XlsxExport.new(result: report).to_xlsx,
     Worklogs::Reports::XlsxExport.new(result: report, detail: true).to_xlsx]
      .all? { |data| data.start_with?("PK") && data.bytesize > 1_000 }
  end

  run.check("the entries behind a report arrive on their own sheet") do
    report = Worklogs::Reports::Result.new(query: Worklogs::Reports::Query.from_params({}), viewer:)
    files = parts.call(Worklogs::Reports::XlsxExport.new(result: report, detail: true).to_xlsx)
    names = Nokogiri::XML(files["xl/workbook.xml"]).css("sheet").map { |sheet| sheet["name"] }

    files.key?("xl/worksheets/sheet2.xml") && names.last == I18n.t("worklogs.reports.detail.sheet")
  end

  # The workbook and the CSV are written from one table on purpose: two readers
  # of the same page must not be able to disagree about what is on it.
  run.check("the workbook and the CSV say the same thing") do
    sheet = Worklogs::Team::Sheet.new(query: Worklogs::Team::Query.from_params({}), viewer:)
    header = Worklogs::Team::ExportTable.new(sheet:).header
    csv_header = CSV.parse_line(Worklogs::Team::CsvExport.new(sheet:).to_csv)
    files = parts.call(Worklogs::Team::XlsxExport.new(sheet:).to_xlsx)
    text = Nokogiri::XML(files["xl/worksheets/sheet1.xml"]).css("t").map(&:text)

    csv_header == header && header.all? { |label| text.include?(label) }
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
