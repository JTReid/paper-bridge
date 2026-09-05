require "test_helper"

class BackfillProfileNamesTest < ActiveSupport::TestCase
  test "splits legacy names without losing surname words and is safe to rerun" do
    original_names = [ "Emma Greenfield", "River", "Ana de la Cruz", "José O’Neill" ]
    profiles = original_names.map do |name|
      id = Dependent.insert_all!([ { account_id: accounts(:greenfield).id, legacy_name: name } ]).first.fetch("id")
      Dependent.find(id)
    end
    entered_profile = Dependent.create!(account: accounts(:greenfield), first_name: "Mary Jane")
    assert_equal original_names, profiles.map(&:name)

    output, = run_script

    assert_includes output, "Backfilled 4 profile names."
    assert_equal [ [ "Emma", "Greenfield" ], [ "River", nil ], [ "Ana", "de la Cruz" ], [ "José", "O’Neill" ] ],
      profiles.map { |profile| profile.reload.attributes.values_at("first_name", "last_name") }
    assert_equal original_names, profiles.map(&:legacy_name)
    assert_equal original_names, profiles.map(&:name)
    assert_equal "Mary Jane", entered_profile.reload.first_name
    assert_nil entered_profile.last_name

    profiles.first.update!(first_name: "Emilia", last_name: "Greenfield")
    output, = run_script

    assert_includes output, "Backfilled 0 profile names."
    assert_equal "Emilia", profiles.first.reload.first_name
  end

  test "reports legacy profiles that need manual correction" do
    Dependent.insert_all!([ { account_id: accounts(:greenfield).id, legacy_name: "  " } ])

    output, error = capture_io do
      exit_error = assert_raises(SystemExit) { load_script("split") }
      assert_equal 1, exit_error.status
    end

    assert_includes output, "Backfilled 0 profile names."
    assert_includes error, "1 profiles still need a first name"
  end

  test "prepares current and newly created names before schema rollback" do
    profile = dependents(:emma)
    profile.update!(first_name: "Emilia", last_name: "de la Cruz")
    new_profile = Dependent.create!(account: accounts(:greenfield), first_name: "Mary Jane")

    run_script("restore")

    assert_equal "Emilia de la Cruz", profile.reload.legacy_name
    assert_equal "Mary Jane", new_profile.reload.legacy_name
  end

  private

    def run_script(mode = "split")
      capture_io { load_script(mode) }
    end

    def load_script(mode)
      previous_arguments = ARGV.dup
      ARGV.replace([ mode ])
      load Rails.root.join("scripts/backfill_profile_names.rb")
    ensure
      ARGV.replace(previous_arguments)
    end
end
