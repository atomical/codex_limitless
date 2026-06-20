# frozen_string_literal: true

require "coverage"

Coverage.start(lines: true)

require "json"
require "minitest/autorun"
require "stringio"
require "time"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "codex_limitless/limits"
require "codex_limitless/cli"

module CodexLimitlessTestSupport
  class TtyStringIO < StringIO
    def tty?
      true
    end
  end

  def run_cli(argv, out: StringIO.new, err: StringIO.new)
    status = CodexLimitless::CLI.new(argv, out: out, err: err).run
    [status, out.string, err.string]
  end

  def stub_limits_summary(summary = nil, callback: nil)
    original = CodexLimitless::Limits.method(:summary)
    implementation = callback || proc { summary }

    CodexLimitless::Limits.define_singleton_method(:summary) do |codex_bin:, limit_id:|
      implementation.call(codex_bin: codex_bin, limit_id: limit_id)
    end

    yield
  ensure
    CodexLimitless::Limits.define_singleton_method(:summary, original)
  end

  def with_stubbed_singleton_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end

  def five_hour_summary(remaining_percent: 15, resets_at_local: past_reset_text)
    {
      "limit_id" => "codex",
      "five_hour" => {
        "remaining_percent" => remaining_percent,
        "resets_at_local" => resets_at_local
      }
    }
  end

  def past_reset_text
    (Time.now - 1).strftime("%Y-%m-%d %I:%M:%S %p %Z")
  end

  def future_reset_text
    (Time.now + 1).strftime("%Y-%m-%d %I:%M:%S %p %Z")
  end
end

Minitest::Test.include(CodexLimitlessTestSupport)

Minitest.after_run do
  result = Coverage.result
  root = File.expand_path("..", __dir__)
  lib_dir = File.join(root, "lib")
  missed = []
  executable_lines = 0
  covered_lines = 0

  result.each do |path, data|
    next unless path.start_with?(lib_dir)
    next unless path.end_with?(".rb")

    lines = data.is_a?(Hash) ? data.fetch(:lines, data["lines"]) : data
    next unless lines

    File.readlines(path).each_with_index do |source, index|
      count = lines[index]
      next if count.nil?

      executable_lines += 1
      if count.zero?
        missed << "#{path.delete_prefix("#{root}/")}:#{index + 1}: #{source.rstrip}"
      else
        covered_lines += 1
      end
    end
  end

  if executable_lines.zero?
    warn "\nCoverage failed: no lib files were tracked."
    exit 1
  end

  if missed.any?
    warn "\nCoverage: #{covered_lines}/#{executable_lines} lines covered."
    warn "Missed lines:"
    missed.each { |line| warn "  #{line}" }
    exit 1
  end

  warn "\nCoverage: 100.00% (#{covered_lines}/#{executable_lines} lines)"
end
