# ---------------------------------------------------------------------------
# Load the first-party engines under /app/plugins without going through bundler.
#
# Why not Gemfile.plugins + `bundle install` (the documented route)? The slim
# runtime image ships no git and no compiler, and `bundle install` re-resolves
# the *whole* Gemfile — which contains git-sourced gems — so it aborts with
# "You need to install git to be able to use gems from git repositories".
#
# Rails does not require an engine to be a gem. Any Rails::Engine subclass that
# exists before `Rails.application.initialize!` is collected as a railtie, and
# config/application.rb instance_evals this file from inside the Application
# class body — which is exactly that window. Engines loaded here therefore get
# their routes, autoload paths, migrations and initializers wired up normally.
#
# Consequence: plugins must be pure Ruby (no gem dependencies of their own) and
# must not need the Angular/webpack pipeline, which the slim image also drops.
# ---------------------------------------------------------------------------
Rails.root.join("plugins").glob("*").sort.each do |plugin_root|
  gemspec_path = plugin_root.glob("*.gemspec").first
  next if gemspec_path.nil?

  # OpenProject::Plugins::ActsAsOpEngine#register reads the plugin's name,
  # author, version and homepage out of Gem.loaded_specs. Nothing loaded us
  # through bundler, so publish the spec ourselves.
  spec = Gem::Specification.load(gemspec_path.to_s)
  Gem.loaded_specs[spec.name] ||= spec

  $LOAD_PATH.unshift plugin_root.join("lib").to_s
  require spec.name
end
