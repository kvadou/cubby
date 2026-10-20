module Detectors
  # Forecasts the next weekday from schedules and flags classrooms where scheduled teaching staff
  # fall short of the stricter of the room's own ratio and the Minnesota ratio for its youngest
  # scheduled child, or where the group exceeds the Minnesota maximum group size (record D13).
  #
  # Limitation: shifts are counted per day, not per hour, so a gap at drop-off or pick-up is not caught.
  class RatioRisk
    KIND = "ratio_risk"
    VERSION = 1
    TEACHING_ROLES = %w[lead_teacher assistant_teacher floater].freeze

    def self.next_operating_day(as_of)
      day = as_of + 1
      day += 1 while day.saturday? || day.sunday?
      day
    end

    def initialize(center, as_of:)
      @center = center
      @as_of = as_of
      @date = self.class.next_operating_day(as_of)
    end

    attr_reader :date

    def call
      @center.classrooms.order(:age_min_months).filter_map { |room| check(room) }
    end

    private

    def check(room)
      children = scheduled_children(room)
      return if children.empty?

      youngest = children.map { |c| c.age_in_months(@date) }.min
      category = Ratios::Minnesota.category_for(youngest)
      ratio = [ room.ratio, category.ratio ].min
      required = (children.size.to_f / ratio).ceil
      staff = teaching_staff_count(room)
      over_group = children.size > category.max_group
      return if staff >= required && !over_group

      problems = []
      problems << "#{staff} teaching staff scheduled for #{children.size} children, #{required} needed at 1:#{ratio}" if staff < required
      problems << "#{children.size} children exceeds the #{category.name} group limit of #{category.max_group}" if over_group

      Candidate.new(
        kind: KIND, subject: room, dedupe_key: "#{KIND}:classroom:#{room.id}:#{@date.iso8601}",
        rationale: "#{room.name} on #{@date.strftime('%A %b %-d')}: #{problems.join('; ')}.",
        facts: {
          classroom_name: room.name,
          date: @date.iso8601,
          expected_children: children.size,
          teaching_staff: staff,
          staff_required: required,
          ratio_applied: ratio,
          youngest_age_months: youngest,
          mn_category: category.name,
          group_size_limit: category.max_group,
          over_group_size: over_group
        },
        occurs_on: @date, detector_version: VERSION
      )
    end

    def scheduled_children(room)
      day = @date.strftime("%a").downcase
      Child.joins(:enrollments).merge(Enrollment.enrolled.where(classroom: room))
           .where("? = ANY(enrollments.schedule_days)", day).to_a
    end

    def teaching_staff_count(room)
      zone = ActiveSupport::TimeZone[@center.timezone]
      window = zone.local(@date.year, @date.month, @date.day).all_day
      room.staff_shifts.joins(:staff_member).where(starts_at: window)
          .where(staff_members: { role: TEACHING_ROLES }).distinct.count(:staff_member_id)
    end
  end
end
