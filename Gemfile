source "https://rubygems.org"

# Specify the Ruby version from .ruby-version file
ruby File.read('.ruby-version').strip

# Core Rails framework
gem "rails", "~> 8.0.2"

# Web server
gem "puma", "~> 6.6.0"

# JSON APIs
gem "jbuilder", "~> 2.11"

# Background processing
gem "solid_queue"

# Caching
gem "solid_cache"

# Aerospike client
gem "aerospike", "~> 2.7.0"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Windows timezone support
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :production do
  # Production-specific gems
  # Add database gem for production if needed
  # gem "pg"
end

group :development, :test do
  # Environment variables management
  gem "dotenv-rails"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Development-specific gems
  gem "sqlite3", "~> 2.6.0"

  # Optional development tools
  # gem "web-console"
  # gem "rack-mini-profiler"
end

group :test do
  # Test-specific gems
  # gem "rspec-rails"
  # gem "factory_bot_rails"
  # gem "capybara"
end
