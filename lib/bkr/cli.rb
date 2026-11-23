# frozen_string_literal: true

require "thor"

module Bkr
  # The `book` command.
  class Cli < Thor
    def self.basename
      "book"
    end

    def self.exit_on_failure?
      true
    end

    map %w[--version -V] => :version

    register(Generators::BookBase, "new", "new NAME", "Create a new book project in the NAME folder")

    desc "build", "Build the book into build/<name>.epub"
    method_option :validate, type: :boolean, default: false, desc: "Validate the EPUB with EPUBCheck after building"
    method_option :verbose, aliases: "-v", type: :boolean, default: false, desc: "Print every build step"
    def build
      project = Project.find(Dir.pwd, verbose: options[:verbose])
      path = Builder.new(project).build
      say_status :build, relative_to_pwd(path), :green
      run_validation(path, project.logger) if options[:validate]
    rescue Bkr::Error => e
      raise Thor::Error, e.message
    ensure
      project&.logger&.close
    end

    desc "validate [EPUB]", "Validate an EPUB with the W3C EPUBCheck (defaults to the project's build)"
    method_option :verbose, aliases: "-v", type: :boolean, default: false, desc: "Print every EPUBCheck message"
    def validate(epub = nil)
      project = Project.find(Dir.pwd, verbose: options[:verbose]) if epub.nil?
      path = epub ? File.expand_path(epub) : project.epub_path
      logger = project ? project.logger : Logger.new(verbose: options[:verbose])
      raise Thor::Error, "No EPUB at #{relative_to_pwd(path)}. Run `book build` first." unless File.exist?(path)

      run_validation(path, logger)
    rescue Bkr::Error => e
      raise Thor::Error, e.message
    ensure
      project&.logger&.close
    end

    desc "version", "Print the bkr version"
    def version
      say "bkr #{Bkr::VERSION}"
    end

    private

    def run_validation(path, logger)
      result = Validator.new(logger: logger).validate(path)
      result.warnings.each { |message| say_status :warning, message, :yellow }
      result.errors.each { |message| say_status :error, message, :red }
      unless result.valid?
        raise Thor::Error, "#{relative_to_pwd(path)} is not a valid EPUB (#{result.errors.size} error(s))"
      end

      say_status :valid, relative_to_pwd(path), :green
    end

    def relative_to_pwd(path)
      path.delete_prefix("#{Dir.pwd}/")
    end
  end
end
