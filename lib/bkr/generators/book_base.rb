module Bkr
  module Generators
    class BookBase < Thor::Group
      include Thor::Actions

      # Define arguments and options
      argument :name, :type => :string, :desc => "The name of the book to create"

      def self.source_root
        File.dirname(__FILE__)
      end

      def create_project
        directory 'templates/book_base', name
      end
    end
  end
end