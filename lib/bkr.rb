# frozen_string_literal: true

require "bkr/version"
require "bkr/errors"
require "bkr/logger"
require "bkr/config"
require "bkr/project"
require "bkr/builder"
require "bkr/validator"
require "bkr/generators"
require "bkr/cli"

# bkr: a framework for creating interactive EPUB 3 books.
module Bkr
  # Bundled CSS/JS libraries shipped with the gem (see lib/bkr/assets).
  ASSETS_DIR = File.expand_path("bkr/assets", __dir__)
end
