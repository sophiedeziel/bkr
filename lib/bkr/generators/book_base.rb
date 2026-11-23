# frozen_string_literal: true

require "thor"
require "date"
require "securerandom"
require "open3"
require "json"

module Bkr
  module Generators
    # `book new NAME`: scaffolds a new book project (see Bkr::Project for the layout).
    class BookBase < Thor::Group
      include Thor::Actions

      FALLBACK_AUTHOR = "Unknown Author"

      argument :name, type: :string, desc: "The name of the book to create"

      def self.source_root
        File.expand_path("templates", __dir__)
      end

      def check_destination
        path = destination_path
        if File.exist?(path) && !File.directory?(path)
          raise Thor::Error, "Cannot create the book: #{name} already exists and is not a directory."
        end
        return unless File.directory?(path) && !Dir.empty?(path)

        raise Thor::Error, "Cannot create the book: the folder #{name} already exists and is not empty. " \
                           "Pick another NAME or remove the folder first."
      end

      def create_project
        directory "book_base", name
        # Stored without the leading dot so git doesn't apply it to the gem's own template folder.
        copy_file "gitignore", File.join(name, ".gitignore")
      end

      def print_next_steps
        say ""
        say "Your book is ready! Next steps:", :green
        say "  cd #{name}"
        say "  # edit config/book.yml and write your chapters in content/"
        say "  book build"
        say "  book validate"
      end

      private

      def destination_path
        File.expand_path(name, destination_root)
      end

      # Used by the templates ----------------------------------------------

      # "my_book" -> "My Book", "the-long-way" -> "The Long Way"
      def book_title
        words = File.basename(name).split(/[\s_\-.]+/).reject(&:empty?)
        words.empty? ? "Untitled Book" : words.map(&:capitalize).join(" ")
      end

      def book_author
        git_user_name || FALLBACK_AUTHOR
      end

      def book_identifier
        "urn:uuid:#{SecureRandom.uuid}"
      end

      def book_date
        Date.today.iso8601
      end

      # Quotes a string for YAML (JSON strings are valid YAML scalars).
      def yaml_string(value)
        value.to_s.to_json
      end

      def git_user_name
        output, status = Open3.capture2("git", "config", "user.name", err: File::NULL)
        value = output.strip
        status.success? && !value.empty? ? value : nil
      rescue SystemCallError
        nil
      end
    end
  end
end
