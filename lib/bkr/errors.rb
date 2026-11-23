# frozen_string_literal: true

module Bkr
  # Base class for every error bkr raises on purpose. The CLI turns these into
  # friendly messages instead of stack traces.
  class Error < StandardError; end

  # Raised when no config/book.yml can be found from the current directory up.
  class ProjectNotFoundError < Error; end

  # Raised when config/book.yml is missing required keys or is malformed.
  class ConfigError < Error; end

  # Raised when the book cannot be built (missing chapters, assets, ...).
  class BuildError < Error; end

  # Raised when Java (needed by EPUBCheck) is not available.
  class JavaMissingError < Error; end
end
