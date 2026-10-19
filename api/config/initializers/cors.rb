# The React director app (Vite dev server locally, CloudFront in AWS) calls this API from another origin.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("CORS_ORIGINS", "http://localhost:5173").split(","))
    resource "/api/*", headers: :any, methods: %i[get post patch put delete options]
  end
end
