# frozen_string_literal: true

require "logger"
require "fileutils"

module Bkr
  # Logs everything to a log file (tmp/bkr.log in a project) and, when verbose,
  # echoes messages to an IO (stdout by default).
  #
  #   log = Bkr::Logger.new(log_path: "tmp/bkr.log", verbose: true)
  #   log.info("Building...")
  class Logger
    LEVELS = %i[debug info warn error].freeze

    attr_reader :log_path

    def initialize(log_path: nil, verbose: false, io: $stdout)
      @log_path = log_path
      @loggers = []

      if log_path
        FileUtils.mkdir_p(File.dirname(log_path))
        file_logger = ::Logger.new(log_path)
        file_logger.level = ::Logger::DEBUG
        file_logger.formatter = proc do |severity, time, _prog, msg|
          "[#{time.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} #{msg}\n"
        end
        @file_logger = file_logger
        @loggers << file_logger
      end

      return unless verbose && io

      console = ::Logger.new(io)
      console.level = ::Logger::DEBUG
      console.formatter = proc { |severity, _time, _prog, msg| "#{severity.downcase.rjust(5)}  #{msg}\n" }
      @loggers << console
    end

    LEVELS.each do |level|
      define_method(level) do |message|
        @loggers.each { |logger| logger.public_send(level, message) }
        nil
      end
    end

    def close
      # Only close the file: closing the console logger would close $stdout.
      @file_logger&.close
    end

    # A logger that discards everything. Handy as a default and in tests.
    def self.null
      new(log_path: nil, verbose: false)
    end
  end
end
