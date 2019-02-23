Gem::Specification.new do |spec|
  spec.name          = 'lita-interrupt'
  spec.version       = '0.1.1'
  spec.authors       = ['Noel Cower']
  spec.email         = ['ncower@gmail.com']
  spec.description   = 'lita-interrupt interrupts a user by assigning them to a new incident in PagerDuty'
  spec.summary       = 'Interrupts people through the power of PagerDuty'
  spec.homepage      = 'https://github.com/nilium/lita-interrupt'
  spec.license       = 'BSD-3-Clause'
  spec.metadata      = { 'lita_plugin_type' => 'handler' }

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.required_ruby_version = '~> 2.3'

  spec.add_runtime_dependency 'lita', '~> 4.7'
  spec.add_runtime_dependency 'pager_duty-connection', '~> 1.0'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'codecov', '~> 0.1.14'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rack-test'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec_junit_formatter'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'simplecov'
end
