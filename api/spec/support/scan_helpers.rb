module ScanHelpers
  MONDAY = Date.new(2026, 10, 19)
  TUESDAY = Date.new(2026, 10, 20)

  def zone = ActiveSupport::TimeZone["America/Chicago"]

  def shift_for(member, room, date)
    create(:staff_shift, staff_member: member, classroom: room,
                         starts_at: zone.local(date.year, date.month, date.day, 8),
                         ends_at: zone.local(date.year, date.month, date.day, 16))
  end

  def enroll(room, birthdate:, days: Enrollment::DAYS, family: nil)
    family ||= create(:family, center: room.center)
    child = create(:child, family: family, birthdate: birthdate)
    create(:enrollment, :enrolled, child: child, classroom: room, schedule_days: days)
  end
end
RSpec.configure { |c| c.include ScanHelpers }
