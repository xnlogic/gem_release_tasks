# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'xn_gem_release_tasks/version'

Gem::Specification.new do |spec|
  spec.name          = "xn_gem_release_tasks"
  spec.version       = XNGemReleaseTasks::VERSION
  spec.authors       = ["Darrick Wiebe"]
  spec.email         = ["dw@xnlogic.com"]
  spec.summary       = %q{Simple set of rake tasks for enforcing development and release consistency}
  spec.description   =
  %q{Develop on .pre branches, only allow releases from non-.pre clean, up-to-date master. Designed to allow Travis CI to do the
     push when on a release version, after passing tests.}
  spec.homepage      = "https://xnlogic.com"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "travis"
  spec.add_development_dependency "builder"
end
