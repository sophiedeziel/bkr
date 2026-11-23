# frozen_string_literal: true

require_relative "lib/bkr/version"

Gem::Specification.new do |spec|
  spec.name          = "bkr"
  spec.version       = Bkr::VERSION
  spec.authors       = ["Sophie Déziel"]
  spec.email         = ["courrier@sophiedeziel.com"]

  spec.summary       = "Framework for creating interactive ePub3 books."
  spec.description   = "bkr scaffolds book projects, builds them into valid EPUB 3 files " \
                       "and validates them with the W3C EPUBCheck."
  spec.homepage      = "https://github.com/sophiedeziel/bkr"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = spec.homepage
  spec.metadata["bug_tracker_uri"]       = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Tracked files plus everything under lib/ (template dotfiles like .keep may be untracked),
  # minus dev-only files and paths deleted but not yet committed.
  dev_only = %w[spec/ bin/setup bin/console .github/ .rubocop .rspec .gitignore .ruby-version Gemfile]
  tracked = Dir.chdir(__dir__) { `git ls-files -z`.split("\x0") }
  spec.files = (tracked | Dir.glob("lib/**/*", File::FNM_DOTMATCH, base: __dir__))
               .reject { |f| f.start_with?(*dev_only) }
               .select { |f| File.file?(File.join(__dir__, f)) }
  spec.bindir        = "bin"
  spec.executables   = ["book"]
  spec.require_paths = ["lib"]

  spec.add_dependency "epubcheck-ruby", "~> 5.3"
  spec.add_dependency "gepub", "~> 2.0"
  spec.add_dependency "logger", "~> 1.6"
  spec.add_dependency "thor", "~> 1.3"
end
