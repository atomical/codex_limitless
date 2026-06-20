# frozen_string_literal: true

require_relative "lib/codex_limitless/version"

Gem::Specification.new do |spec|
  spec.name = "codex_limitless"
  spec.version = CodexLimitless::VERSION
  spec.authors = ["Adam"]

  spec.summary = "Inspect Codex usage limits and wait for reset windows."
  spec.description = "A CLI gem that reads Codex app-server rate limit data and waits for five-hour reset times."
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir.chdir(__dir__) do
    Dir["README.md", "lib/**/*.rb", "exe/*"].select { |path| File.file?(path) }
  end
  spec.bindir = "exe"
  spec.executables = ["codex-limitless"]
  spec.require_paths = ["lib"]
end
