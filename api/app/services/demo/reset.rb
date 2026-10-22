require "faker"

module Demo
  # Puts the demo back to its seeded state: every table emptied (sessions too, so visitors start over),
  # the fictional center re-seeded with dates relative to today, and a scan so the inbox has work.
  class Reset
    # demo_visits records who tried the demo and from where; it outlives resets on purpose.
    KEEP = %w[schema_migrations ar_internal_metadata demo_visits].freeze

    def initialize(seed: -> { Rails.application.load_seed })
      @seed = seed
    end

    def call
      raise "Demo::Reset only runs in a demo deployment" unless Demo.deployed? || Rails.env.test?
      # A second guard that doesn't depend on configuration: demo data has only fictional .test logins,
      # so a database with any real address is never wiped, whatever CUBBY_DEMO says.
      raise "Demo::Reset refuses a database with non-demo users" if User.where.not("email_address LIKE ?", "%.test").exists?

      connection = ActiveRecord::Base.connection
      connection.truncate_tables(*(connection.tables - KEEP))
      # Seeds pick unique fake names; a long-lived Sidekiq process would otherwise run out of them.
      Faker::UniqueGenerator.clear
      @seed.call
      Center.find_each { |center| CenterScan.new(center).call }
    end
  end
end
