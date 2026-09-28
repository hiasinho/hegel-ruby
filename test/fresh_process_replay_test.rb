# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class FreshProcessReplayTest < Minitest::Test
  PROJECT_ROOT = File.expand_path("..", __dir__)
  FIXTURE = File.join(PROJECT_ROOT, "test/fixtures/fresh_process_replay.rb")

  def test_replays_a_saved_failure_in_a_fresh_process
    Dir.mktmpdir do |directory|
      payload_path = File.join(directory, "failure.json")

      run_fixture("discover", payload_path)
      discovered = JSON.parse(File.read(payload_path))

      run_fixture("replay", payload_path)
      replayed = JSON.parse(File.read(payload_path))

      refute_equal discovered.fetch("process_id"), replayed.fetch("process_id")
      assert_operator discovered.fetch("property_invocations"), :>, 1
      assert_equal 1, replayed.fetch("property_invocations")
      assert_equal [ 5 ], discovered.fetch("drawn_values")
      assert_equal discovered.fetch("blob"), replayed.fetch("blob")
      assert_equal discovered.fetch("drawn_values"), replayed.fetch("drawn_values")
      assert_equal discovered.fetch("error_message"), replayed.fetch("error_message")
      assert_equal discovered.fetch("origin"), replayed.fetch("origin")
    end
  end

  private
    def run_fixture(mode, payload_path)
      command = [
        RbConfig.ruby,
        "-rbundler/setup",
        "-Ilib",
        FIXTURE,
        mode,
        payload_path
      ]
      stdout, stderr, status = Open3.capture3(*command, chdir: PROJECT_ROOT)

      assert status.success?, <<~MESSAGE
        Fresh-process #{mode} failed with status #{status.exitstatus}.
        stdout:
        #{stdout}
        stderr:
        #{stderr}
      MESSAGE
    end
end
