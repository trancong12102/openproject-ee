Gem::Specification.new do |s|
  s.name        = "openproject-worklogs"
  s.version     = File.read(File.expand_path("lib/open_project/worklogs/version.rb", __dir__))[/VERSION = "([^"]+)"/, 1]
  s.authors     = "JMango360"
  s.summary     = "OpenProject Worklogs"
  s.description = "Timesheets, multi-dimensional time reports and approvals for OpenProject"
  s.license     = "GPL-3.0-or-later"
  s.homepage    = "https://github.com/jmango360/openproject-ee"

  s.required_ruby_version = ">= 3.4"
  s.files = Dir["{app,config,db,lib,public}/**/*", "README.md"]
  s.metadata["rubygems_mfa_required"] = "false"
end
