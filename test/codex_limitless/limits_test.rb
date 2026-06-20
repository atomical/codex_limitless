# frozen_string_literal: true

require_relative "../test_helper"

module CodexLimitless
  class LimitsTest < Minitest::Test
    def test_summary_shapes_selected_limit_snapshot
      five_hour_reset = Time.local(2026, 6, 20, 12, 0, 0).to_i
      weekly_reset = Time.local(2026, 6, 24, 12, 0, 0).to_i
      raw = {
        "rateLimitsByLimitId" => {
          "codex" => {
            "limitId" => "codex",
            "limitName" => "Codex",
            "planType" => "pro",
            "primary" => {
              "windowDurationMins" => 300,
              "usedPercent" => 85,
              "resetsAt" => five_hour_reset
            },
            "secondary" => {
              "windowDurationMins" => 10_080,
              "usedPercent" => 5,
              "resetsAt" => weekly_reset
            }
          }
        },
        "rateLimitResetCredits" => { "available" => 1 }
      }

      seen_codex_bin = nil
      with_stubbed_singleton_method(Limits, :fetch_rate_limits, proc { |codex_bin|
        seen_codex_bin = codex_bin
        raw
      }) do
        summary = Limits.summary(codex_bin: "codex-bin", limit_id: "codex")

        assert_equal "codex-bin", seen_codex_bin
        assert_equal "codex", summary.fetch("limit_id")
        assert_equal "Codex", summary.fetch("limit_name")
        assert_equal "pro", summary.fetch("plan_type")
        assert_equal 15, summary.fetch("five_hour").fetch("remaining_percent")
        assert_equal 95, summary.fetch("weekly").fetch("remaining_percent")
        assert_equal({ "available" => 1 }, summary.fetch("rate_limit_reset_credits"))
        assert_match(/\A2026-06-20 12:00:00 PM /, summary.fetch("five_hour").fetch("resets_at_local"))
        assert_match(/\A2026-06-20T12:00:00/, summary.fetch("five_hour").fetch("resets_at_iso8601"))
      end
    end

    def test_summary_falls_back_to_legacy_snapshot_and_window_keys
      raw = {
        "rateLimits" => {
          "primary" => {
            "windowDurationMins" => 60,
            "usedPercent" => -10
          },
          "secondary" => {
            "windowDurationMins" => 120,
            "usedPercent" => 150
          }
        }
      }

      with_stubbed_singleton_method(Limits, :fetch_rate_limits, proc { |*| raw }) do
        summary = Limits.summary(codex_bin: "codex", limit_id: "fallback")

        assert_equal "fallback", summary.fetch("limit_id")
        assert_equal 100, summary.fetch("five_hour").fetch("remaining_percent")
        assert_equal 0, summary.fetch("weekly").fetch("remaining_percent")
      end
    end

    def test_summary_raises_when_no_snapshot_exists
      with_stubbed_singleton_method(Limits, :fetch_rate_limits, proc { |*| {} }) do
        error = assert_raises(Error) do
          Limits.summary(codex_bin: "codex", limit_id: "missing")
        end

        assert_includes error.message, "No rate limit snapshot found"
      end
    end

    def test_window_summary_handles_nil_window
      summary = Limits.window_summary(nil)

      assert_nil summary.fetch("window_duration_mins")
      assert_nil summary.fetch("used_percent")
      assert_nil summary.fetch("remaining_percent")
      assert_nil summary.fetch("resets_at")
      assert_nil summary.fetch("resets_at_local")
      assert_nil summary.fetch("resets_at_iso8601")
    end

    def test_fetch_rate_limits_initializes_reads_and_closes_client
      fake_class = Class.new do
        class << self
          attr_accessor :last
        end

        attr_reader :codex_bin, :requests

        def initialize(codex_bin)
          @codex_bin = codex_bin
          @requests = []
          @closed = false
          self.class.last = self
        end

        def request(method, params: nil)
          @requests << [method, params]
          return { "ok" => true } if method == "account/rateLimits/read"

          { "initialized" => true }
        end

        def close
          @closed = true
        end

        def closed?
          @closed
        end
      end

      original = AppServerClient
      CodexLimitless.send(:remove_const, :AppServerClient)
      CodexLimitless.const_set(:AppServerClient, fake_class)

      result = Limits.fetch_rate_limits("custom-codex")
      client = fake_class.last

      assert_equal({ "ok" => true }, result)
      assert_equal "custom-codex", client.codex_bin
      assert_equal "initialize", client.requests.fetch(0).fetch(0)
      assert_equal "codex-limitless", client.requests.fetch(0).fetch(1).fetch("clientInfo").fetch("name")
      assert_equal VERSION, client.requests.fetch(0).fetch(1).fetch("clientInfo").fetch("version")
      assert_equal "account/rateLimits/read", client.requests.fetch(1).fetch(0)
      assert client.closed?
    ensure
      CodexLimitless.send(:remove_const, :AppServerClient)
      CodexLimitless.const_set(:AppServerClient, original)
    end
  end
end
