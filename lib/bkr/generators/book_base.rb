module Bkr
  module Generators
    class BookBase < Thor::Group
      include Thor::Actions

      # Define arguments and options
      argument :name

      def self.create_project
        directory 'book', name
      end
    end
  end
end