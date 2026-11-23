# frozen_string_literal: true

module Bkr
  class Builder
    # EPUB 3.3 core media types for the files bkr puts in a package.
    # https://www.w3.org/TR/epub-33/#sec-core-media-types
    module MediaTypes
      TYPES = {
        ".xhtml" => "application/xhtml+xml",
        ".css" => "text/css",
        ".js" => "text/javascript",
        ".gif" => "image/gif",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".png" => "image/png",
        ".svg" => "image/svg+xml",
        ".webp" => "image/webp",
        ".otf" => "font/otf",
        ".ttf" => "font/ttf",
        ".woff" => "font/woff",
        ".woff2" => "font/woff2"
      }.freeze

      # Returns the media type for path's extension, or nil if bkr doesn't know it.
      def self.for(path)
        TYPES[File.extname(path).downcase]
      end

      def self.image?(path)
        self.for(path)&.start_with?("image/") || false
      end
    end
  end
end
