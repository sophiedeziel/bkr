# frozen_string_literal: true

require "pathname"

module Bkr
  class Builder
    # A file that goes into the package: where it comes from on disk, where it
    # goes inside the package (relative to the OPF) and its media type.
    Resource = Struct.new(:source, :href, :media_type, keyword_init: true)

    # A chapter listed in (or discovered for) the config, before it is parsed.
    ChapterSource = Struct.new(:source, :title, keyword_init: true)

    # Finds every source file of a project (chapters, stylesheets, scripts,
    # images, fonts) and checks that the files named in config/book.yml exist
    # and stay inside the project.
    class Sources
      CHAPTER_GLOB = "*.{html,xhtml}"
      MEDIA_GLOB = "{images,fonts}/**/*"
      BUNDLED_HREF_DIR = "bkr"

      def initialize(project)
        @project = project
        @config = project.config
      end

      # Chapters in reading order: config.chapters, or every content/*.html and
      # content/*.xhtml sorted by filename.
      def chapters
        list = @config.chapters || discovered_chapters
        if list.empty?
          raise BuildError, "No chapters to build. Add .html files to #{display(@project.content_dir)}/ " \
                            "or list them under `chapters:` in #{display(@project.config_path)}."
        end

        list.map do |chapter|
          source = resolve(@project.content_dir, chapter.file, "chapters")
          unless File.file?(source)
            raise BuildError, "Chapter file not found: #{display(source)} (listed under `chapters:` " \
                              "in #{display(@project.config_path)})"
          end

          ChapterSource.new(source: source, title: chapter.title)
        end
      end

      # Bundled bkr stylesheets (when enabled) followed by the author's.
      def stylesheets
        bundled("css") + authored(@config.stylesheets, "css/*.css", setting: "stylesheets", extension: ".css")
      end

      # Bundled bkr scripts (when enabled) followed by the author's.
      def scripts
        bundled("js") + authored(@config.scripts, "js/*.js", setting: "scripts", extension: ".js")
      end

      def cover
        return nil if @config.cover.nil?

        source = resolve(@project.assets_dir, @config.cover, "cover")
        unless File.file?(source)
          raise BuildError, "Cover image not found: #{display(source)} (`cover:` in #{display(@project.config_path)})"
        end
        unless MediaTypes.image?(source)
          raise BuildError, "Cover #{display(source)} must be a PNG, JPEG, GIF, SVG or WebP image"
        end

        asset(source)
      end

      # Every file under assets/images and assets/fonts, recursively (dotfiles skipped).
      def media
        Dir.glob(MEDIA_GLOB, base: @project.assets_dir).sort.filter_map do |relative|
          source = File.join(@project.assets_dir, relative)
          next unless File.file?(source)

          if MediaTypes.for(source).nil?
            @project.logger.warn("Skipping #{display(source)}: not an EPUB core media type")
            next
          end

          asset(source)
        end
      end

      # A path relative to the project root, for messages.
      def display(path)
        path.delete_prefix("#{@project.root}/")
      end

      private

      def discovered_chapters
        Dir.glob(CHAPTER_GLOB, base: @project.content_dir).sort.map do |file|
          Config::Chapter.new(file: file, title: nil)
        end
      end

      def bundled(extension)
        return [] unless @config.bkr_assets? && Dir.exist?(Bkr::ASSETS_DIR)

        Dir.glob("*.#{extension}", base: Bkr::ASSETS_DIR).sort.map do |file|
          source = File.join(Bkr::ASSETS_DIR, file)
          Resource.new(source: source, href: "#{BUNDLED_HREF_DIR}/#{file}", media_type: MediaTypes.for(source))
        end
      end

      def authored(list, default_glob, setting:, extension:)
        return Dir.glob(default_glob, base: @project.assets_dir).sort.map { |rel| asset(asset_path(rel)) } if list.nil?

        list.map do |relative|
          source = resolve(@project.assets_dir, relative, setting)
          unless File.file?(source)
            raise BuildError, "File not found: #{display(source)} (listed under `#{setting}:` " \
                              "in #{display(@project.config_path)})"
          end
          unless File.extname(source).casecmp?(extension)
            raise BuildError, "#{display(source)} is listed under `#{setting}:` but is not a #{extension} file"
          end

          asset(source)
        end
      end

      def asset_path(relative)
        File.join(@project.assets_dir, relative)
      end

      # assets/<path> goes to <path> in the package.
      def asset(source)
        href = Pathname.new(source).relative_path_from(Pathname.new(@project.assets_dir)).to_s
        Resource.new(source: source, href: href, media_type: MediaTypes.for(source))
      end

      # Expands a path from config/book.yml, refusing anything outside base_dir.
      def resolve(base_dir, relative, setting)
        expanded = File.expand_path(relative, base_dir) unless relative.start_with?("~")
        return expanded if expanded&.start_with?("#{base_dir}/") && !Pathname.new(relative).absolute?

        raise BuildError, "`#{setting}:` entry #{relative.inspect} in #{display(@project.config_path)} must be " \
                          "a relative path inside #{display(base_dir)}/ (no absolute paths or '..')"
      end
    end
  end
end
