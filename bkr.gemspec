# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bkr/version'

Gem::Specification.new do |spec|
  spec.name          = "bkr"
  spec.version       = Bkr::VERSION
  spec.authors       = ["Sophie Déziel"]
  spec.email         = ["courrier@sophiedeziel.com"]

  spec.summary       = %q{Framework for creating interactive ePub3 books.}
  spec.homepage      = "https://github.com/sophiedeziel/bkr"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.executables   = ["book"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_dependency 'thor', "~> 0.19"
end
