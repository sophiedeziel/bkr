# frozen_string_literal: true

require "nokogiri"
require "pathname"

module Bkr
  class Builder
    # One chapter: an XHTML body fragment from content/ turned into a complete
    # XHTML5 content document.
    class Chapter
      XHTML_NS = "http://www.w3.org/1999/xhtml"
      EPUB_NS = "http://www.idpf.org/2007/ops"
      NS = { "x" => XHTML_NS }.freeze
      WRAPPER_OPEN = %(<body xmlns="#{XHTML_NS}" xmlns:epub="#{EPUB_NS}">).freeze
      VOID_ELEMENTS = %w[area base br col embed hr img input link meta source track wbr].freeze
      URL_ATTRIBUTES = %w[href src poster data].freeze
      MAX_REPORTED_ERRORS = 5

      attr_reader :source, :href, :display_path

      # source: absolute path of the fragment; href: its path in the package;
      # display_path: source relative to the project root (for messages).
      def initialize(source:, href:, display_path:, title: nil)
        @source = source
        @href = href
        @display_path = display_path
        @configured_title = title
        @fragment = parse
      end

      # Config title, then the first h1, then the first h2, then the file name.
      def title
        @title ||= presence(@configured_title) || heading("h1") || heading("h2") || humanized_name
      end

      # The complete XHTML document. links maps absolute source paths to package
      # hrefs so links between chapters and to assets keep working.
      def to_xhtml(language:, stylesheets: [], scripts: [], links: {})
        doc = Nokogiri::XML(document_template(language, stylesheets, scripts)) { |config| config.strict.nonet }
        body = doc.at_xpath("//x:body", NS)
        content = @fragment.root.dup
        rewrite_links(content, links)
        body.add_child(content.children)
        expand_empty_elements(doc)
        doc.to_xml(encoding: "UTF-8")
      end

      # The href of target (a package path) relative to this chapter.
      def relative_href(target)
        Pathname.new(target).relative_path_from(Pathname.new(File.dirname(href))).to_s
      end

      private

      def parse
        text = File.read(source, encoding: "UTF-8").delete_prefix("﻿")
        raise BuildError, "#{display_path} is not valid UTF-8" unless text.valid_encoding?

        # The wrapper sits on line 1, so parser line numbers match the file's.
        doc = Nokogiri::XML("#{WRAPPER_OPEN}#{text}</body>") { |config| config.recover.nonet }
        errors = doc.errors.select { |error| error.error? || error.fatal? }
        raise BuildError, syntax_error_message(errors) if errors.any? || doc.root.nil?

        doc
      end

      def syntax_error_message(errors)
        lines = errors.first(MAX_REPORTED_ERRORS).map do |error|
          column = error.line == 1 ? error.column - WRAPPER_OPEN.length : error.column
          # Nokogiri prefixes messages with "line:col: LEVEL: "; we print our own location.
          message = error.message.strip.sub(/\A\d+:\d+: [A-Z]+: /, "")
          "  #{display_path}:#{error.line}:#{column}: #{message}"
        end
        "#{display_path} is not well-formed XHTML (chapters are XHTML body fragments: close every tag, " \
          "quote attributes, use numeric entities like &#160; instead of &nbsp;):\n#{lines.join("\n")}"
      end

      def heading(name)
        node = @fragment.at_xpath("//x:#{name}", NS)
        presence(node&.text&.gsub(/\s+/, " "))
      end

      def humanized_name
        base = File.basename(source, ".*")
        name = base.sub(/\A\d+[\s_.-]*/, "")
        name = base if name.empty?
        name = name.tr("_-", " ").squeeze(" ").strip
        name[0].upcase + name[1..]
      end

      def presence(text)
        text = text&.strip
        text.nil? || text.empty? ? nil : text
      end

      def document_template(language, stylesheets, scripts)
        lang = language.encode(xml: :attr)
        head = ["<meta charset=\"UTF-8\"/>", "<title>#{title.encode(xml: :text)}</title>"]
        head += stylesheets.map { |res| %(<link rel="stylesheet" type="text/css" href=#{attr_href(res)}/>) }
        head += scripts.map { |res| %(<script src=#{attr_href(res)}></script>) }
        <<~XHTML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE html>
          <html xmlns="#{XHTML_NS}" xmlns:epub="#{EPUB_NS}" xml:lang=#{lang} lang=#{lang}>
          <head>
          #{head.join("\n")}
          </head>
          <body>
          </body>
          </html>
        XHTML
      end

      def attr_href(resource)
        relative_href(resource.href).encode(xml: :attr)
      end

      # Points relative links at files bkr moved (content/*.html -> text/*.xhtml,
      # assets/x -> x). Links bkr doesn't know about are left alone.
      def rewrite_links(root, links)
        root.xpath(".//*[@href or @src or @poster or @data]").each do |node|
          URL_ATTRIBUTES.each do |name|
            node[name] = rewrite_link(node[name], links) if node[name]
          end
        end
      end

      def rewrite_link(value, links)
        return value if value.empty? || value.start_with?("#", "/") || value.match?(/\A[a-z][a-z0-9+.-]*:/i)

        path, anchor = value.split("#", 2)
        target = links[File.expand_path(path, File.dirname(source))]
        return value if target.nil?

        anchor ? "#{relative_href(target)}##{anchor}" : relative_href(target)
      end

      # <script src="..."/> is risky in HTML-ish readers: give every empty
      # non-void element an explicit end tag.
      def expand_empty_elements(doc)
        doc.xpath("//x:*[not(node())]", NS).each do |node|
          next if VOID_ELEMENTS.include?(node.name)

          node.add_child(doc.create_text_node(""))
        end
      end
    end
  end
end
