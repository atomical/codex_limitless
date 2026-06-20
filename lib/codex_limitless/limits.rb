# frozen_string_literal: true

require "json"
require "open3"
require "time"
require "timeout"

require_relative "version"

module CodexLimitless
  unless const_defined?(:Error, false)
    class Error < StandardError; end
  end

  class AppServerClient
    REQUEST_TIMEOUT_SECONDS = Integer(ENV.fetch("CODEX_USAGE_TIMEOUT", "30"))

    def initialize(codex_bin)
      @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(codex_bin, "app-server", "--stdio")
      @stderr_reader = Thread.new { @stderr.read }
      @next_id = 0
    rescue Errno::ENOENT
      raise Error, "Could not find `#{codex_bin}`. Set CODEX_BIN to the Codex CLI path."
    end

    def request(method, params: nil)
      id = next_request_id
      payload = { "jsonrpc" => "2.0", "id" => id, "method" => method }
      payload["params"] = params unless params.nil?

      @stdin.puts(JSON.generate(payload))
      @stdin.flush

      read_response(id)
    end

    def close
      @stdin.close unless @stdin.closed?

      Timeout.timeout(2) { @wait_thread.value }
    rescue Timeout::Error
      Process.kill("TERM", @wait_thread.pid)
      @wait_thread.value
    ensure
      @stderr_reader&.join(0.2)
    end

    private

    def next_request_id
      @next_id += 1
    end

    def read_response(id)
      deadline = Time.now + REQUEST_TIMEOUT_SECONDS

      loop do
        line = read_line(deadline)
        message = JSON.parse(line)
        next unless message["id"] == id

        raise response_error(message) if message["error"]

        return message["result"]
      end
    end

    def read_line(deadline)
      remaining = deadline - Time.now
      raise Timeout::Error, "Timed out waiting for Codex app-server" if remaining <= 0

      line = Timeout.timeout(remaining) { @stdout.gets }
      return line if line

      stderr = @stderr_reader&.value.to_s.strip
      details = stderr.empty? ? "" : ": #{stderr}"
      raise Error, "Codex app-server exited before responding#{details}"
    end

    def response_error(message)
      error = message["error"]
      code = error["code"] || "unknown"
      text = error["message"] || error.inspect
      Error.new("Codex app-server request failed (#{code}): #{text}")
    end
  end

  module Limits
    module_function

    def summary(codex_bin:, limit_id:)
      rate_limits = fetch_rate_limits(codex_bin)
      snapshot = select_limit_snapshot(rate_limits, limit_id)
      raise Error, "No rate limit snapshot found for limit id `#{limit_id}`" unless snapshot

      {
        "limit_id" => snapshot["limitId"] || limit_id,
        "limit_name" => snapshot["limitName"],
        "plan_type" => snapshot["planType"],
        "five_hour" => window_summary(select_window(snapshot, 300, "primary")),
        "weekly" => window_summary(select_window(snapshot, 10_080, "secondary")),
        "rate_limit_reset_credits" => rate_limits["rateLimitResetCredits"]
      }
    end

    def fetch_rate_limits(codex_bin)
      client = AppServerClient.new(codex_bin)
      client.request(
        "initialize",
        params: {
          "clientInfo" => {
            "name" => "codex-limitless",
            "title" => nil,
            "version" => VERSION
          },
          "capabilities" => {
            "experimentalApi" => true,
            "requestAttestation" => false,
            "optOutNotificationMethods" => []
          }
        }
      )
      client.request("account/rateLimits/read")
    ensure
      client&.close
    end

    def select_limit_snapshot(rate_limits, limit_id)
      by_id = rate_limits["rateLimitsByLimitId"] || {}
      by_id[limit_id] || rate_limits["rateLimits"]
    end

    def select_window(snapshot, duration_mins, fallback_key)
      windows = [snapshot["primary"], snapshot["secondary"]].compact
      windows.find { |window| window["windowDurationMins"].to_i == duration_mins } || snapshot[fallback_key]
    end

    def window_summary(window)
      used_percent = window&.fetch("usedPercent", nil)
      remaining_percent = used_percent.nil? ? nil : [[100 - used_percent.to_i, 0].max, 100].min
      resets_at = window&.fetch("resetsAt", nil)

      {
        "window_duration_mins" => window&.fetch("windowDurationMins", nil),
        "used_percent" => used_percent,
        "remaining_percent" => remaining_percent,
        "resets_at" => resets_at,
        "resets_at_local" => resets_at ? Time.at(resets_at).strftime("%Y-%m-%d %I:%M:%S %p %Z") : nil,
        "resets_at_iso8601" => resets_at ? Time.at(resets_at).iso8601 : nil
      }
    end
  end
end
