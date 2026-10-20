# Fictional demo data. Each file is idempotent; `bin/rails db:seed:replant` rebuilds everything.
# Development, or a deployed demo that opts in with CUBBY_DEMO=1. The demo directors' local password
# is public in this repo, so production requires DEMO_PASSWORD (db/seeds/demo_users.rb).
return unless Rails.env.development? || ENV["CUBBY_DEMO"] == "1"

load Rails.root.join("db/seeds/little_oaks.rb")
load Rails.root.join("db/seeds/demo_users.rb")
load Rails.root.join("db/seeds/policies.rb")
