# frozen_string_literal: true

require "yaml"
require "date"

module Bkr
  # The book's metadata and structure, read from config/book.yml.
  #
  #   title: "My Book"                 # required
  #   author: "Jane Doe"               # required (string or list of strings)
  #   language: en                     # required (BCP 47 tag)
  #   identifier: "urn:uuid:..."       # required, unique per book
  #   publisher: "Me"                  # optional
  #   description: "..."               # optional
  #   date: 2026-11-22                 # optional, publication date
  #   filename: my_book                # optional, name of build/<filename>.epub
  #   cover: images/cover.png          # optional, relative to assets/
  #   bkr_assets: true                 # optional, include bundled bkr.css/bkr.js (default true)
  #   stylesheets: [css/book.css]      # optional, relative to assets/ (default: every assets/css/*.css)
  #   scripts: [js/book.js]            # optional, relative to assets/ (default: every assets/js/*.js)
  #   chapters:                        # optional (default: every content/*.html, sorted)
  #     - file: introduction.html      #   relative to content/
  #       title: Introduction          #   optional, defaults to the chapter's first heading
  #     - chapter_one.html             #   short form
  class Config
    REQUIRED_KEYS = %w[title author language identifier].freeze

    Chapter = Struct.new(:file, :title, keyword_init: true)

    attr_reader :path, :title, :authors, :language, :identifier, :publisher, :description,
                :date, :filename, :cover, :stylesheets, :scripts, :chapters

    def self.load(path)
      raise ConfigError, "Config file not found: #{path}" unless File.exist?(path)

      data = YAML.safe_load_file(path, permitted_classes: [Date, Time]) || {}
      raise ConfigError, "#{path} must contain a YAML mapping (key: value pairs)" unless data.is_a?(Hash)

      new(data, path: path)
    rescue Psych::Exception => e
      raise ConfigError, "#{path} is not valid YAML: #{e.message}"
    end

    def initialize(data, path: nil)
      @path = path
      data = data.transform_keys(&:to_s)
      validate_required!(data)

      @title       = data["title"].to_s
      @authors     = Array(data["author"]).map(&:to_s)
      @language    = data["language"].to_s
      @identifier  = data["identifier"].to_s
      @publisher   = data["publisher"]&.to_s
      @description = data["description"]&.to_s
      @date        = data["date"]
      @filename    = parse_filename(data["filename"])
      @cover       = data["cover"]&.to_s
      @bkr_assets  = data.fetch("bkr_assets", true) ? true : false
      @stylesheets = optional_list(data, "stylesheets")
      @scripts     = optional_list(data, "scripts")
      @chapters    = parse_chapters(data["chapters"])
    end

    def author
      authors.first
    end

    def bkr_assets?
      @bkr_assets
    end

    private

    def validate_required!(data)
      missing = REQUIRED_KEYS.select { |key| Array(data[key]).all? { |value| value.to_s.strip.empty? } }
      return if missing.empty?

      raise ConfigError, "#{path || 'config'} is missing required key(s): #{missing.join(', ')}"
    end

    # The EPUB is written to build/<filename>.epub, so it must be a plain file name.
    def parse_filename(raw)
      return nil if raw.nil?

      name = raw.to_s.strip.delete_suffix(".epub")
      if name.empty? || name.match?(%r{[/\\]}) || name.start_with?(".")
        raise ConfigError, "filename must be a plain file name like my_book (got #{raw.inspect})"
      end

      name
    end

    # nil means "not configured, use the default"; a list means "exactly these".
    def optional_list(data, key)
      return nil unless data.key?(key)

      Array(data[key]).map(&:to_s)
    end

    def parse_chapters(raw)
      return nil if raw.nil?
      raise ConfigError, "chapters must be a list" unless raw.is_a?(Array)

      raw.map do |entry|
        case entry
        when String then Chapter.new(file: entry, title: nil)
        when Hash
          entry = entry.transform_keys(&:to_s)
          raise ConfigError, "each chapter needs a file: #{entry.inspect}" unless entry["file"]

          Chapter.new(file: entry["file"].to_s, title: entry["title"]&.to_s)
        else
          raise ConfigError, "invalid chapter entry: #{entry.inspect}"
        end
      end
    end
  end
end
