# The public demo: fictional data that anyone can try with one click and that rebuilds itself nightly.
# On in development and in a deployment that sets CUBBY_DEMO=1; the nightly reset runs only in the latter,
# so it never wipes a developer's local data.
module Demo
  DIRECTOR_EMAIL = "renee@littleoaks.test".freeze

  def self.enabled? = Rails.env.development? || deployed?
  def self.deployed? = ENV["CUBBY_DEMO"] == "1"

  def self.director = User.find_by(email_address: DIRECTOR_EMAIL)
end
