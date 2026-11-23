# frozen_string_literal: true

module Bkr
  # A book project on disk: the folder containing config/book.yml.
  #
  #   my_book/
  #   ├── config/book.yml   metadata and chapter order
  #   ├── content/          chapters (*.html body fragments)
  #   ├── assets/           css/, js/, images/, fonts/
  #   ├── build/            generated .epub files
  #   └── tmp/              bkr.log and scratch files
  class Project
    CONFIG_FILE = File.join("config", "book.yml")

    attr_reader :root

    # Walks up from start_dir until it finds a folder containing config/book.yml.
    def self.find(start_dir = Dir.pwd, **options)
      dir = File.expand_path(start_dir)
      loop do
        return new(dir, **options) if File.exist?(File.join(dir, CONFIG_FILE))

        parent = File.dirname(dir)
        if parent == dir
          raise ProjectNotFoundError,
                "No bkr project found (looked for #{CONFIG_FILE} in #{File.expand_path(start_dir)} " \
                "and its parents). Create one with `book new NAME`."
        end
        dir = parent
      end
    end

    def initialize(root, verbose: false, logger: nil)
      @root = File.expand_path(root)
      @verbose = verbose
      @logger = logger
    end

    def config
      @config ||= Config.load(config_path)
    end

    def logger
      @logger ||= Logger.new(log_path: log_path, verbose: @verbose)
    end

    def config_path = File.join(root, CONFIG_FILE)
    def content_dir = File.join(root, "content")
    def assets_dir  = File.join(root, "assets")
    def build_dir   = File.join(root, "build")
    def tmp_dir     = File.join(root, "tmp")
    def log_path    = File.join(tmp_dir, "bkr.log")

    # build/<filename>.epub, where filename comes from the config or the folder name.
    def epub_path
      name = config.filename || File.basename(root)
      File.join(build_dir, "#{name}.epub")
    end
  end
end
