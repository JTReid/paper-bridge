require "test_helper"

class AppointmentTest < ActiveSupport::TestCase
  test "fixture is valid and belongs to a dependent and account" do
    appointment = appointments(:emma_therapy)

    assert_predicate appointment, :valid?
    assert_equal dependents(:emma), appointment.dependent
    assert_equal accounts(:greenfield), appointment.account
    assert_includes accounts(:greenfield).appointments, appointment
  end

  test "requires a scheduled time" do
    appointment = appointments(:emma_therapy).dup
    appointment.scheduled_at = nil

    assert_not appointment.valid?
    assert_includes appointment.errors[:scheduled_at], "can't be blank"
  end

  test "requires a description" do
    appointment = appointments(:emma_therapy).dup
    appointment.description = nil

    assert_not appointment.valid?
    assert_includes appointment.errors[:description], "can't be blank"
  end

  test "is removed with its dependent" do
    dependent = Dependent.create!(account: accounts(:greenfield), name: "Appointment Profile")
    appointment = dependent.appointments.create!(
      scheduled_at: Time.zone.local(2026, 7, 23, 9),
      description: "Annual review"
    )

    dependent.destroy!

    assert_not Appointment.exists?(appointment.id)
  end
end
