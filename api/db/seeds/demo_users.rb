# Demo sign-ins for local development. A second center with its own director makes tenancy visible:
# signing in as either director shows only that director's center.
#
# The password is a fictional local demo value, not a secret. Override it with DEMO_PASSWORD.
password = ENV.fetch("DEMO_PASSWORD", "littleoaks-demo")

little_oaks = Center.find_by!(name: "Little Oaks Early Learning")
birchwood = Center.find_or_create_by!(name: "Birchwood Kids Club") do |c|
  c.city = "St. Paul"
  c.timezone = "America/Chicago"
  c.director_name = "Marcus Lindqvist"
end
birchwood.classrooms.find_or_create_by!(name: "Robins") do |r|
  r.age_min_months = 33
  r.age_max_months = 60
  r.capacity = 12
  r.ratio = 10
end

[
  [ "Renee Albright", "renee@littleoaks.test", little_oaks ],
  [ "Marcus Lindqvist", "marcus@birchwood.test", birchwood ]
].each do |name, email, center|
  user = User.find_or_create_by!(email_address: email) do |u|
    u.name = name
    u.password = password
  end
  user.memberships.find_or_create_by!(center: center)
end

puts "Demo directors: renee@littleoaks.test (Little Oaks), marcus@birchwood.test (Birchwood)."
