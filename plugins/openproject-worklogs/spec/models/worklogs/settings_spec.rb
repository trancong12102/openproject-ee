require "spec_helper"

RSpec.describe Worklogs::Settings do
  describe ".sanitise" do
    it "casts what an HTML form actually sends" do
      cast = described_class.sanitise(
        "approvals_enabled" => "1",
        "lock_approved_periods" => "0",
        "allow_self_approval" => "",
        "reminders_enabled" => "1",
        "reminder_weekday" => "3",
        "reminder_hour" => "17",
        "reminder_tolerance" => "1.25"
      )

      expect(cast).to eq(
        "approvals_enabled" => true,
        "lock_approved_periods" => false,
        "allow_self_approval" => false,
        "reminders_enabled" => true,
        "reminder_weekday" => 3,
        "reminder_hour" => 17,
        "reminder_tolerance" => 1.25
      )
    end

    # An unchecked checkbox is not submitted at all, so a missing key has to mean
    # false rather than "leave it as it was".
    it "reads an absent checkbox as off" do
      expect(described_class.sanitise({})["approvals_enabled"]).to be(false)
    end

    it "falls back instead of storing an impossible value" do
      cast = described_class.sanitise("reminder_weekday" => "99", "reminder_hour" => "-4",
                                      "reminder_tolerance" => "-3")

      expect(cast["reminder_weekday"]).to eq(described_class::DEFAULTS["reminder_weekday"])
      expect(cast["reminder_hour"]).to eq(described_class::DEFAULTS["reminder_hour"])
      expect(cast["reminder_tolerance"]).to eq(0)
    end

    it "writes every key, so a partial form cannot leave a stale value behind" do
      expect(described_class.sanitise("approvals_enabled" => "1").keys)
        .to match_array(described_class::DEFAULTS.keys)
    end
  end

  describe "reading" do
    before { described_class.invalidate! }

    after do
      Setting.plugin_openproject_worklogs = described_class::DEFAULTS.dup
      described_class.invalidate!
    end

    it "fills in defaults for keys the stored hash has never heard of" do
      Setting.plugin_openproject_worklogs = { "reminders_enabled" => true }
      described_class.invalidate!

      expect(described_class.current.reminders_enabled?).to be(true)
      expect(described_class.current.approvals_enabled?).to be(true)
      expect(described_class.current.reminder_hour).to eq(8)
    end

    # Approval without locking is a real way to work. Locking without approval
    # is not a thing at all — there would be nothing to lock on.
    it "reports locking as off whenever approvals are off" do
      Setting.plugin_openproject_worklogs = { "approvals_enabled" => false,
                                              "lock_approved_periods" => true }
      described_class.invalidate!

      expect(described_class.current.lock_approved_periods?).to be(false)
    end

    it "answers the same question the same way twice within a request" do
      Setting.plugin_openproject_worklogs = { "approvals_enabled" => true }
      described_class.invalidate!
      first = described_class.current

      expect(described_class.current).to be(first)
    end
  end
end
