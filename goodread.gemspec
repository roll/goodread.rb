# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "goodread"
  spec.version       = "0.3.1"
  spec.authors       = ["Evgeny Karev\n"]
  spec.email         = ["eskarev@gmail.com"]

  spec.summary       = "Test runner for README.md. Support for Python/JavaScript/Ruby/PHP code blocks. Integration with hackmd.io."
  spec.description   = "Test runner for README.md. Support for Python/JavaScript/Ruby/PHP code blocks. Integration with hackmd.io."
  spec.homepage      = "https://github.com/goodread/goodread-rb"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.bindir        = "bin"
  spec.executables   = ["goodread-rb"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"

  spec.add_dependency "colorize", "~> 0.8"
  spec.add_dependency "gemoji", "~> 3.0"
end
