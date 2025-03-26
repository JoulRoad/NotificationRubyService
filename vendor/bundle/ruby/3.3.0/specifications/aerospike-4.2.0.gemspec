# -*- encoding: utf-8 -*-
# stub: aerospike 4.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "aerospike".freeze
  s.version = "4.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Khosrow Afroozeh".freeze, "Jan Hecking".freeze, "Sachin Venkatesha Murthy".freeze]
  s.date = "2024-12-17"
  s.description = "Official Aerospike Client for ruby. Access your Aerospike cluster with ease of Ruby.".freeze
  s.email = ["khosrow@aerospike.com".freeze, "jhecking@aerospike.com".freeze, "smurthy@aerospike.com".freeze]
  s.homepage = "http://www.github.com/aerospike/aerospike-client-ruby".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.post_install_message = "Thank you for using Aerospike!\nYou can report issues on github.com/aerospike/aerospike-client-ruby".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)
  s.rubygems_version = "3.5.11".freeze
  s.summary = "An Aerospike driver for Ruby.".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<msgpack>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<bcrypt>.freeze, ["~> 3.1".freeze])
end
