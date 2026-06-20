# frozen_string_literal: true

require "json"
require "optparse"
require "time"

require_relative "../codex_limitless"

module CodexLimitless
  class CLI
    DEFAULT_PERCENTAGE = 15

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
    end

    def run
      options = {
        codex_bin: ENV.fetch("CODEX_BIN", "codex"),
        limit_id: ENV.fetch("CODEX_LIMIT_ID", "codex"),
        percentage: DEFAULT_PERCENTAGE,
        command: nil
      }
      parser = option_parser(options)
      parser.parse!(@argv)

      case options[:command]
      when :limits
        print_limits(options)
      when :wait
        wait_for_five_hour_reset(options)
      when :auto
        auto_wait_for_five_hour_reset(options)
      when :version
        @out.puts VERSION
      else
        @out.puts parser
      end

      0
    rescue OptionParser::ParseError => e
      @err.puts "Error: #{e.message}"
      @err.puts
      @err.puts option_parser(default_options)
      1
    rescue StandardError => e
      @err.puts "Error: #{e.message}"
      1
    end

    private

    def default_options
      {
        codex_bin: ENV.fetch("CODEX_BIN", "codex"),
        limit_id: ENV.fetch("CODEX_LIMIT_ID", "codex"),
        percentage: DEFAULT_PERCENTAGE,
        command: nil
      }
    end

    def option_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: codex-limitless [options]"
        parser.separator ""
        parser.separator "Commands:"

        parser.on("-l", "--limits", "Fetch and print Codex limit information as JSON.") do
          set_command(options, :limits)
        end

        parser.on("-w", "--wait", "Wait until five_hour.resets_at_local from the fetched JSON.") do
          set_command(options, :wait)
        end

        parser.on("-a", "--auto", "Wait only when five_hour.remaining_percent is at or below --percentage.") do
          set_command(options, :auto)
        end

        parser.separator ""
        parser.separator "Options:"

        parser.on("--limit-id LIMIT_ID", "Codex rate limit id to inspect (default: #{options[:limit_id]}).") do |limit_id|
          options[:limit_id] = limit_id
        end

        parser.on("--codex-bin PATH", "Codex CLI path (default: #{options[:codex_bin]}).") do |codex_bin|
          options[:codex_bin] = codex_bin
        end

        parser.on("-p", "--percentage PERCENT", Integer, "Auto wait threshold percentage (default: #{options[:percentage]}).") do |percentage|
          raise OptionParser::ParseError, "percentage must be between 0 and 100" unless percentage.between?(0, 100)

          options[:percentage] = percentage
        end

        parser.on("-v", "--version", "Print the codex_limitless version.") do
          set_command(options, :version)
        end

        parser.on("-h", "--help", "Show this help message.") do
          set_command(options, :help)
        end
      end
    end

    def set_command(options, command)
      return options[:command] = command if command == :help
      return if options[:command] == :help
      return options[:command] = command if options[:command].nil? || options[:command] == command

      raise OptionParser::ParseError, "choose only one command"
    end

    def print_limits(options)
      @out.puts JSON.pretty_generate(fetch_summary(options))
    end

    def wait_for_five_hour_reset(options)
      summary = fetch_summary(options)
      wait_until_five_hour_reset(summary)
    end

    def auto_wait_for_five_hour_reset(options)
      summary = fetch_summary(options)
      remaining_percent = summary.dig("five_hour", "remaining_percent")
      raise Error, "five_hour.remaining_percent is missing from the fetched limit JSON" if remaining_percent.nil?

      threshold = options[:percentage]
      if remaining_percent.to_i > threshold
        @out.puts "Five-hour remaining is #{remaining_percent}%, above #{threshold}%; not waiting."
        return
      end

      @out.puts "Five-hour remaining is #{remaining_percent}%, at or below #{threshold}%; waiting."
      wait_until_five_hour_reset(summary)
    end

    def wait_until_five_hour_reset(summary)
      reset_text = five_hour_reset_text(summary)
      reset_at = Time.parse(reset_text)
      @out.puts "Waiting until five-hour reset at #{reset_text}."

      until Time.now >= reset_at
        remaining = [(reset_at - Time.now).ceil, 0].max
        print_wait_status(remaining) if tty?
        sleep 1
      end

      @out.puts if tty?
      @out.puts "Five-hour reset reached at #{Time.now.strftime("%Y-%m-%d %I:%M:%S %p %Z")}."
    end

    def five_hour_reset_text(summary)
      reset_text = summary.dig("five_hour", "resets_at_local")
      raise Error, "five_hour.resets_at_local is missing from the fetched limit JSON" if reset_text.nil? || reset_text.empty?

      reset_text
    end

    def fetch_summary(options)
      Limits.summary(codex_bin: options[:codex_bin], limit_id: options[:limit_id])
    end

    def print_wait_status(remaining)
      @out.print "\r#{format_duration(remaining)} remaining"
      @out.flush
    end

    def format_duration(seconds)
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60
      format("%02d:%02d:%02d", hours, minutes, secs)
    end

    def tty?
      @out.respond_to?(:tty?) && @out.tty?
    end
  end
end
