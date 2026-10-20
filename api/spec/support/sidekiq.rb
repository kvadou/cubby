require "sidekiq/testing"
Sidekiq::Testing.fake!
RSpec.configure { |config| config.before { Sidekiq::Worker.clear_all } }
