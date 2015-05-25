require 'bkr/generators/book_base'

module Bkr
  class Cli < Thor
    register(Bkr::Generators::BookBase, "new", "name", "creates a new book project")
  end
end