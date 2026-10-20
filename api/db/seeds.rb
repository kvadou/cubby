# Fictional demo data. Each file is idempotent; `bin/rails db:seed:replant` rebuilds everything.
# Development only: the demo directors share a password that is public in this repo, and
# `db:prepare` runs seeds on a fresh database, including a first production deploy.
return unless Rails.env.development?

load Rails.root.join("db/seeds/little_oaks.rb")
load Rails.root.join("db/seeds/demo_users.rb")
load Rails.root.join("db/seeds/policies.rb")
