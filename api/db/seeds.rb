# Fictional demo data. Each file is idempotent; `bin/rails db:seed:replant` rebuilds everything.
return if Rails.env.test?

load Rails.root.join("db/seeds/little_oaks.rb")
load Rails.root.join("db/seeds/demo_users.rb")
