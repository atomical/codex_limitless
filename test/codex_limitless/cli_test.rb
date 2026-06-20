# frozen_string_literal: true

require_relative "../test_helper"

module CodexLimitless
  class CLITest < Minitest::Test
    def test_no_arguments_prints_help
      status, out, err = run_cli([])

      assert_equal 0, status
      assert_empty err
      assert_includes out, "Usage: codex-limitless"
      assert_includes out, "--auto"
    end

    def test_help_takes_precedence_over_later_commands
      status, out, err = run_cli(["--help", "--limits"])

      assert_equal 0, status
      assert_empty err
      assert_includes out, "Usage: codex-limitless"
    end

    def test_version_prints_version
      status, out, err = run_cli(["--version"])

      assert_equal 0, status
      assert_empty err
      assert_equal "#{VERSION}\n", out
    end

    def test_limits_prints_json_and_uses_cli_options
      callback = proc do |codex_bin:, limit_id:|
        assert_equal "/usr/local/bin/codex", codex_bin
        assert_equal "team", limit_id
        {
          "limit_id" => limit_id,
          "five_hour" => {
            "remaining_percent" => 42,
            "resets_at_local" => past_reset_text
          }
        }
      end

      stub_limits_summary(callback: callback) do
        status, out, err = run_cli(["-l", "--limits", "--limit-id", "team", "--codex-bin", "/usr/local/bin/codex"])

        assert_equal 0, status
        assert_empty err
        assert_equal "team", JSON.parse(out).fetch("limit_id")
      end
    end

    def test_wait_polls_until_reset_and_prints_tty_status
      out = TtyStringIO.new
      summary = five_hour_summary(resets_at_local: future_reset_text)

      stub_limits_summary(summary) do
        status, _out, err = run_cli(["--wait"], out: out)

        assert_equal 0, status
        assert_empty err
        assert_includes out.string, "Waiting until five-hour reset"
        assert_includes out.string, "remaining"
        assert_includes out.string, "Five-hour reset reached"
      end
    end

    def test_auto_does_not_wait_when_remaining_percent_is_above_default_threshold
      stub_limits_summary(five_hour_summary(remaining_percent: 16)) do
        status, out, err = run_cli(["-a"])

        assert_equal 0, status
        assert_empty err
        assert_equal "Five-hour remaining is 16%, above 15%; not waiting.\n", out
      end
    end

    def test_auto_waits_when_remaining_percent_is_at_default_threshold
      stub_limits_summary(five_hour_summary(remaining_percent: 15)) do
        status, out, err = run_cli(["--auto"])

        assert_equal 0, status
        assert_empty err
        assert_includes out, "Five-hour remaining is 15%, reset at"
        assert_includes out, "00:00:00 remaining"
        assert_includes out, "Five-hour reset reached"
      end
    end

    def test_auto_refreshes_remaining_percent_every_minute_while_waiting
      summaries = [
        five_hour_summary(remaining_percent: 7, resets_at_local: future_reset_text(seconds: 60)),
        five_hour_summary(remaining_percent: 6, resets_at_local: past_reset_text)
      ]
      call_count = 0
      callback = proc do |**|
        summary = summaries.fetch([call_count, summaries.length - 1].min)
        call_count += 1
        summary
      end

      with_auto_refresh_seconds(0) do
        stub_limits_summary(callback: callback) do
          status, out, err = run_cli(["--auto"])

          assert_equal 0, status
          assert_empty err
          assert_equal 2, call_count
          assert_match(/Five-hour remaining is 7%, reset at .*\rFive-hour remaining is 6%, reset at /, out)
          refute_match(/Five-hour remaining is 7%, reset at .*\nFive-hour remaining is 6%, reset at /, out)
          assert_includes out, "Five-hour reset reached"
        end
      end
    end

    def test_auto_percentage_option_overrides_threshold
      stub_limits_summary(five_hour_summary(remaining_percent: 20)) do
        status, out, err = run_cli(["--auto", "--percentage", "20"])

        assert_equal 0, status
        assert_empty err
        assert_includes out, "Five-hour remaining is 20%, reset at"
      end
    end

    def test_auto_errors_when_remaining_percent_is_missing
      stub_limits_summary({ "five_hour" => { "resets_at_local" => past_reset_text } }) do
        status, out, err = run_cli(["--auto"])

        assert_equal 1, status
        assert_empty out
        assert_includes err, "five_hour.remaining_percent is missing"
      end
    end

    def test_wait_errors_when_reset_text_is_missing
      stub_limits_summary({ "five_hour" => { "remaining_percent" => 1 } }) do
        status, out, err = run_cli(["--wait"])

        assert_equal 1, status
        assert_empty out
        assert_includes err, "five_hour.resets_at_local is missing"
      end
    end

    def test_invalid_percentage_prints_help_and_fails
      status, out, err = run_cli(["--auto", "--percentage", "101"])

      assert_equal 1, status
      assert_empty out
      assert_includes err, "percentage must be between 0 and 100"
      assert_includes err, "Usage: codex-limitless"
    end

    def test_conflicting_commands_print_help_and_fail
      status, out, err = run_cli(["--limits", "--wait"])

      assert_equal 1, status
      assert_empty out
      assert_includes err, "choose only one command"
      assert_includes err, "Usage: codex-limitless"
    end

    def test_standard_errors_are_reported
      stub_limits_summary(callback: proc { raise Error, "boom" }) do
        status, out, err = run_cli(["--limits"])

        assert_equal 1, status
        assert_empty out
        assert_equal "Error: boom\n", err
      end
    end
  end
end
