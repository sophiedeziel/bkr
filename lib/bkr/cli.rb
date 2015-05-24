require 'thor'

module Bkr
  class Cli < Thor
    desc "new NAME", "This will create a new book project"
    long_desc <<-NEW_NAME

    `new NAME` will create a new book project.

    NEW_NAME
    #option :upcase
    def new( name )
      Bkr::Generators::BookBase.start(name: name)
    end
  end
end