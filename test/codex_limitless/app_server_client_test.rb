# frozen_string_literal: true

require_relative "../test_helper"

module CodexLimitless
  class AppServerClientTest < Minitest::Test
    FakeWaitThread = Struct.new(:pid) do
      attr_reader :value_calls

      def initialize(pid = 1234)
        super(pid)
        @value_calls = 0
      end

      def value
        @value_calls += 1
        :done
      end
    end

    def test_request_writes_json_rpc_payload_and_reads_matching_response
      stdin = StringIO.new
      stdout = StringIO.new(
        "#{JSON.generate({ "id" => 99, "result" => "ignored" })}\n" \
        "#{JSON.generate({ "id" => 1, "result" => { "ok" => true } })}\n"
      )
      stderr = StringIO.new("")
      wait_thread = FakeWaitThread.new
      popen_args = nil

      with_stubbed_popen3(stdin, stdout, stderr, wait_thread) do |args|
        popen_args = args
        client = AppServerClient.new("codex")
        result = client.request("example/read", params: { "x" => 1 })
        client.close

        assert_equal({ "ok" => true }, result)
      end

      payload = JSON.parse(stdin.string.lines.first)
      assert_equal ["codex", "app-server", "--stdio"], popen_args
      assert_equal "2.0", payload.fetch("jsonrpc")
      assert_equal 1, payload.fetch("id")
      assert_equal "example/read", payload.fetch("method")
      assert_equal({ "x" => 1 }, payload.fetch("params"))
      assert stdin.closed?
      assert_equal 1, wait_thread.value_calls
    end

    def test_request_raises_response_errors
      stdin = StringIO.new
      stdout = StringIO.new("#{JSON.generate({ "id" => 1, "error" => {} })}\n")
      stderr = StringIO.new("")
      wait_thread = FakeWaitThread.new

      with_stubbed_popen3(stdin, stdout, stderr, wait_thread) do
        client = AppServerClient.new("codex")
        error = assert_raises(Error) { client.request("broken") }
        client.close

        assert_includes error.message, "unknown"
      end
    end

    def test_request_raises_when_process_exits_before_responding
      stdin = StringIO.new
      stdout = StringIO.new("")
      stderr = StringIO.new("stderr details")
      wait_thread = FakeWaitThread.new

      with_stubbed_popen3(stdin, stdout, stderr, wait_thread) do
        client = AppServerClient.new("codex")
        error = assert_raises(Error) { client.request("missing") }
        client.close

        assert_includes error.message, "Codex app-server exited before responding: stderr details"
      end
    end

    def test_read_line_raises_when_deadline_has_passed
      stdin = StringIO.new
      stdout = StringIO.new("")
      stderr = StringIO.new("")
      wait_thread = FakeWaitThread.new

      with_stubbed_popen3(stdin, stdout, stderr, wait_thread) do
        client = AppServerClient.new("codex")
        error = assert_raises(Timeout::Error) { client.send(:read_line, Time.now - 1) }
        client.close

        assert_equal "Timed out waiting for Codex app-server", error.message
      end
    end

    def test_close_terminates_process_when_wait_thread_times_out
      stdin = StringIO.new
      stdout = StringIO.new("")
      stderr = StringIO.new("")
      wait_thread = FakeWaitThread.new(4321)
      killed = []

      with_stubbed_popen3(stdin, stdout, stderr, wait_thread) do
        with_stubbed_singleton_method(Timeout, :timeout, proc { |*| raise Timeout::Error }) do
          with_stubbed_singleton_method(Process, :kill, proc { |signal, pid| killed << [signal, pid] }) do
            AppServerClient.new("codex").close
          end
        end
      end

      assert_equal [["TERM", 4321]], killed
      assert_equal 1, wait_thread.value_calls
    end

    def test_initialize_raises_when_codex_binary_is_missing
      with_stubbed_singleton_method(Open3, :popen3, proc { |*| raise Errno::ENOENT }) do
        error = assert_raises(Error) { AppServerClient.new("missing-codex") }

        assert_includes error.message, "Could not find `missing-codex`"
      end
    end

    private

    def with_stubbed_popen3(stdin, stdout, stderr, wait_thread)
      captured_args = []
      with_stubbed_singleton_method(Open3, :popen3, proc { |*args|
        captured_args.replace(args)
        [stdin, stdout, stderr, wait_thread]
      }) do
        yield captured_args
      end
    end
  end
end
