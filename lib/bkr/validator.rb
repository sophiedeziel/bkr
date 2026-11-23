# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "epubcheck/ruby/cli"
require "epubcheck/ruby/version"

module Bkr
  # Validates an EPUB with the W3C EPUBCheck bundled in the epubcheck-ruby gem.
  # EPUBCheck is a Java program, so Java 11+ must be installed.
  #
  #   result = Bkr::Validator.new(logger: logger).validate("build/my_book.epub")
  #   result.valid?   # => false
  #   result.errors   # => ["RSC-005: Error while parsing file: ... (EPUB/text/ch1.xhtml:12:4)"]
  #
  # Each EPUBCheck message becomes one string: "ID: message (location, ...)".
  # Locations are "path:line:column" (line/column omitted when unknown). A
  # message reported at several places stays a single entry listing all of its
  # locations, so the error count matches the number of distinct problems.
  class Validator
    Result = Struct.new(:errors, :warnings, keyword_init: true) do
      def valid? = errors.empty?
    end

    JAR_FILE = Epubcheck::Ruby::CLI::JAR_FILE
    EPUBCHECK_VERSION = Epubcheck::Ruby::VERSION.split(".").first(2).join(".")
    MINIMUM_JAVA_VERSION = 11
    ERROR_SEVERITIES = %w[FATAL ERROR].freeze
    WARNING_SEVERITIES = %w[WARNING].freeze

    JAVA_MISSING_MESSAGE = <<~MSG.chomp
      EPUBCheck needs Java #{MINIMUM_JAVA_VERSION} or newer, but %<problem>s.
      Install a Java runtime (e.g. `brew install openjdk` on macOS, your package manager on Linux,
      or https://adoptium.net) and make sure `java` is on your PATH.
    MSG

    # runner: anything responding to call(*argv) and returning [stdout, stderr, Process::Status],
    # like Open3.capture3. Injected so specs don't need Java.
    def initialize(logger: Logger.null, runner: Open3.method(:capture3))
      @logger = logger
      @runner = runner
    end

    # Returns a Result. Raises JavaMissingError if Java is not installed and
    # Bkr::Error if there is no file at epub_path.
    def validate(epub_path)
      path = File.expand_path(epub_path)
      raise Error, "No EPUB at #{path}" unless File.exist?(path)

      check_java!
      @logger.info("Validating #{path} with EPUBCheck #{EPUBCHECK_VERSION}")
      result = Dir.mktmpdir("bkr-epubcheck") { |dir| run_epubcheck(path, File.join(dir, "report.json")) }
      log_summary(result)
      result
    end

    private

    def check_java!
      stdout, stderr, status = @runner.call("java", "-version")
      output = "#{stdout}#{stderr}"
      java_missing!("`java -version` failed") if !status.success? || output.include?("Unable to locate a Java Runtime")

      version = java_major_version(output)
      java_missing!("Java #{version} is installed") if version && version < MINIMUM_JAVA_VERSION
      @logger.debug("Java: #{output.lines.first&.strip}")
    rescue Errno::ENOENT
      java_missing!("`java` was not found")
    end

    def java_missing!(problem)
      raise JavaMissingError, format(JAVA_MISSING_MESSAGE, problem: problem)
    end

    # `java -version` prints e.g. `openjdk version "21.0.2"` or `java version "1.8.0_391"`.
    def java_major_version(output)
      match = output.match(/version "(\d+)(?:\.(\d+))?/)
      return unless match

      match[1] == "1" ? match[2].to_i : match[1].to_i
    end

    def run_epubcheck(path, report_path)
      command = ["java", "-jar", JAR_FILE, path, "--json", report_path]
      @logger.debug("Running: #{command.join(' ')}")
      stdout, stderr, status = @runner.call(*command)
      report = read_report(report_path)
      return result_from_report(report) if report

      @logger.debug("EPUBCheck produced no JSON report. stdout: #{stdout.strip} stderr: #{stderr.strip}")
      result_from_output("#{stdout}\n#{stderr}", status)
    end

    def read_report(report_path)
      return unless File.exist?(report_path)

      report = JSON.parse(File.read(report_path))
      report if report.is_a?(Hash) && report["messages"].is_a?(Array)
    rescue JSON::ParserError
      nil
    end

    def result_from_report(report)
      result = Result.new(errors: [], warnings: [])
      report["messages"].each do |message|
        severity = message["severity"].to_s.upcase
        text = format_message(message)
        @logger.debug("EPUBCheck #{severity}: #{text}")
        if ERROR_SEVERITIES.include?(severity)
          result.errors << text
        elsif WARNING_SEVERITIES.include?(severity)
          result.warnings << text
        end
      end
      result
    end

    # Fallback when EPUBCheck crashed before writing its report.
    def result_from_output(output, status)
      errors = output.lines.map(&:strip).grep(/\b(?:ERROR|FATAL)\b/)
      return Result.new(errors: errors, warnings: []) if errors.any?

      failure = "EPUBCheck failed (exit status #{status.exitstatus.inspect}) without producing a report"
      Result.new(errors: [failure], warnings: [])
    end

    def format_message(message)
      text = "#{message['ID']}: #{message['message'].to_s.strip}"
      locations = Array(message["locations"]).filter_map { |location| format_location(location) }
      extra = message["additionalLocations"].to_i
      locations << "and #{extra} more" if extra.positive?
      locations.empty? ? text : "#{text} (#{locations.join(', ')})"
    end

    # EPUBCheck uses -1 for unknown line/column numbers.
    def format_location(location)
      return unless location.is_a?(Hash) && location["path"]

      [location["path"], location["line"], location["column"]]
        .take_while { |part| part.is_a?(String) || part.to_i.positive? }
        .join(":")
    end

    def log_summary(result)
      if result.valid?
        @logger.info("EPUBCheck: no errors, #{result.warnings.size} warning(s)")
      else
        @logger.info("EPUBCheck: #{result.errors.size} error(s), #{result.warnings.size} warning(s)")
      end
    end
  end
end
