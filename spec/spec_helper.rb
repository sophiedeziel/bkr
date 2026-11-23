# frozen_string_literal: true

require "bkr"
require "tmpdir"
require "fileutils"

module SpecHelpers
  # Runs the block inside a fresh temporary directory and cleans up afterwards.
  def in_tmpdir(&block)
    Dir.mktmpdir("bkr-spec") { |dir| Dir.chdir(dir) { block.call(dir) } }
  end

  # Runs the `book` CLI in-process and returns [stdout, stderr].
  # Thor::Error (and exit) are captured instead of aborting the test run.
  def run_cli(*args)
    out = StringIO.new
    err = StringIO.new
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = out
    $stderr = err
    begin
      Bkr::Cli.start(args.map(&:to_s))
    rescue SystemExit
      # exit_on_failure? makes Thor exit; keep running the suite.
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
    [out.string, err.string]
  end

  # Path to the in-repo fixtures directory.
  def fixture_path(*parts)
    File.join(__dir__, "fixtures", *parts)
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Specs tagged :java need a real Java runtime for EPUBCheck.
  java_available = system("java", "-version", out: File::NULL, err: File::NULL)
  config.filter_run_excluding(:java) unless java_available
end
