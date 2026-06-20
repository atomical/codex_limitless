# frozen_string_literal: true

require "json"
require "optparse"
require "time"

require_relative "../codex_limitless"

module CodexLimitless
  class CLI
    DEFAULT_PERCENTAGE = 15
    AUTO_REFRESH_SECONDS = 60

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
      @status_line_width = 0
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

        parser.on("-a", "--auto", "Wait when five_hour.remaining_percent is at or below --percentage; refresh every minute.") do
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
      remaining_percent = five_hour_remaining_percent(summary)

      threshold = options[:percentage]
      if remaining_percent.to_i > threshold
        @out.puts "Five-hour remaining is #{remaining_percent}%, above #{threshold}%; not waiting."
        return
      end

      current_remaining_percent = remaining_percent
      status_message = proc do |remaining, reset_text|
        "Five-hour remaining is #{current_remaining_percent}%, reset at #{reset_text} " \
          "(#{format_duration(remaining)} remaining)"
      end

      wait_until_five_hour_reset(
        summary,
        refresh_seconds: AUTO_REFRESH_SECONDS,
        status_message: status_message
      ) do
        refreshed = fetch_summary(options)
        current_remaining_percent = five_hour_remaining_percent(refreshed)
        refreshed
      end
    end

    def wait_until_five_hour_reset(summary, refresh_seconds: nil, status_message: nil, &refresh_summary)
      reset_text = five_hour_reset_text(summary)
      reset_at = Time.parse(reset_text)
      next_refresh_at = refresh_summary ? Time.now + refresh_seconds : nil
      @out.puts "Waiting until five-hour reset at #{reset_text}." unless status_message
      print_status_line(status_message.call(seconds_until(reset_at), reset_text)) if status_message

      until Time.now >= reset_at
        if next_refresh_at && Time.now >= next_refresh_at
          summary = refresh_summary.call
          reset_text = five_hour_reset_text(summary)
          reset_at = Time.parse(reset_text)
          next_refresh_at = Time.now + refresh_seconds
        end

        remaining = seconds_until(reset_at)
        if status_message
          print_status_line(status_message.call(remaining, reset_text))
        elsif tty?
          print_wait_status(remaining)
        end
        break if Time.now >= reset_at

        sleep 1
      end

      status_message ? finish_status_line : (@out.puts if tty?)
      @out.puts "Five-hour reset reached at #{Time.now.strftime("%Y-%m-%d %I:%M:%S %p %Z")}."
    end

    def five_hour_remaining_percent(summary)
      remaining_percent = summary.dig("five_hour", "remaining_percent")
      raise Error, "five_hour.remaining_percent is missing from the fetched limit JSON" if remaining_percent.nil?

      remaining_percent
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

    def print_status_line(message)
      padding_width = [@status_line_width - message.length, 0].max
      prefix = @status_line_width.zero? ? "" : "\r"
      @out.print "#{prefix}#{message}#{" " * padding_width}"
      @out.flush
      @status_line_width = message.length
    end

    def finish_status_line
      @out.puts
      @status_line_width = 0
    end

    def seconds_until(time)
      [(time - Time.now).ceil, 0].max
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
