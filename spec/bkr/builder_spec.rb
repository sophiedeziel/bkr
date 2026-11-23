# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "zip"
require "nokogiri"

RSpec.describe Bkr::Builder do
  let(:root) { File.join(Dir.pwd, "sample_book") }
  let(:project) { Bkr::Project.new(root, logger: Bkr::Logger.null) }
  let(:namespaces) do
    {
      "opf" => "http://www.idpf.org/2007/opf",
      "dc" => "http://purl.org/dc/elements/1.1/",
      "x" => "http://www.w3.org/1999/xhtml",
      "epub" => "http://www.idpf.org/2007/ops"
    }
  end

  around { |example| in_tmpdir { example.run } }

  before do
    FileUtils.cp_r(fixture_path("sample_book"), root)
    bundled = File.join(Dir.pwd, "bundled_assets")
    FileUtils.mkdir_p(bundled)
    File.write(File.join(bundled, "bkr.css"), "body { margin: 0; }\n")
    File.write(File.join(bundled, "bkr.js"), "window.bkr = {};\n")
    stub_const("Bkr::ASSETS_DIR", bundled)
  end

  def build
    described_class.new(project).build
  end

  # Merges changes into config/book.yml; a nil value removes the key.
  def update_config(changes)
    path = File.join(root, "config", "book.yml")
    data = YAML.safe_load_file(path, permitted_classes: [Date])
    changes.each { |key, value| value.nil? ? data.delete(key.to_s) : data[key.to_s] = value }
    File.write(path, YAML.dump(data))
  end

  def write_file(relative, content)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def read_entry(name)
    Zip::File.open(project.epub_path) { |zip| zip.read(name) }.force_encoding("UTF-8")
  end

  def entry_names
    Zip::File.open(project.epub_path) { |zip| zip.entries.map(&:name) }
  end

  def opf
    Nokogiri::XML(read_entry("OEBPS/package.opf"), &:strict)
  end

  def chapter(href)
    Nokogiri::XML(read_entry("OEBPS/#{href}"), &:strict)
  end

  def manifest_item(href)
    opf.at_xpath("//opf:manifest/opf:item[@href='#{href}']", namespaces)
  end

  def spine_hrefs
    doc = opf
    doc.xpath("//opf:spine/opf:itemref/@idref", namespaces).map do |idref|
      doc.at_xpath("//opf:item[@id='#{idref.value}']/@href", namespaces).value
    end
  end

  def nav_titles
    nav = Nokogiri::XML(read_entry("OEBPS/nav.xhtml"))
    nav.xpath("//x:nav[@epub:type='toc']//x:a", namespaces).map { |a| [a.text, a["href"]] }
  end

  describe "#build" do
    it "writes build/<filename>.epub and returns its absolute path" do
      path = build

      expect(path).to eq(File.join(root, "build", "sample_book.epub"))
      expect(File.file?(path)).to be(true)
    end

    it "stores an uncompressed mimetype as the first zip entry" do
      build

      Zip::File.open(project.epub_path) do |zip|
        first = zip.entries.first
        expect(first.name).to eq("mimetype")
        expect(first.compression_method).to eq(Zip::Entry::STORED)
        expect(zip.read(first)).to eq("application/epub+zip")
      end
    end

    it "writes the mimetype local header without an extra field (EPUBCheck PKG-005)" do
      build
      bytes = File.binread(project.epub_path, 58)

      expect(bytes[0, 4].unpack1("V")).to eq(0x04034b50) # local file header signature
      expect(bytes[8, 2].unpack1("v")).to eq(0)          # compression method: stored
      expect(bytes[26, 2].unpack1("v")).to eq(8)         # file name length
      expect(bytes[28, 2].unpack1("v")).to eq(0)         # extra field length
      expect(bytes[30, 8]).to eq("mimetype")
      expect(bytes[38, 20]).to eq("application/epub+zip")
    end

    it "points META-INF/container.xml at the package document" do
      build

      container = Nokogiri::XML(read_entry("META-INF/container.xml"))
      rootfile = container.at_xpath("//c:rootfile", "c" => "urn:oasis:names:tc:opendocument:xmlns:container")
      expect(rootfile["full-path"]).to eq("OEBPS/package.opf")
      expect(rootfile["media-type"]).to eq("application/oebps-package+xml")
    end

    it "writes the book metadata to the OPF" do
      build
      doc = opf

      unique_id = doc.root["unique-identifier"]
      expect(doc.at_xpath("//dc:identifier[@id='#{unique_id}']", namespaces).text)
        .to eq("urn:uuid:3f1c7a52-8d4e-4b6a-9c2f-5e0d1a7b9c44")
      expect(doc.xpath("//dc:title", namespaces).map(&:text)).to eq(["The Sample Book"])
      expect(doc.xpath("//dc:creator", namespaces).map(&:text)).to eq(["Ada Lovelace", "Charles Babbage"])
      expect(doc.xpath("//dc:language | //dc:date | //dc:publisher", namespaces).map(&:text))
        .to eq(["en", "bkr Test Press", "2026-11-22"]).or eq(["en", "2026-11-22", "bkr Test Press"])
      expect(doc.at_xpath("//opf:meta[@property='dcterms:modified']", namespaces).text)
        .to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/)
    end

    it "lists chapters, stylesheets, scripts and images in the manifest" do
      build

      expect(manifest_item("text/01_introduction.xhtml")["media-type"]).to eq("application/xhtml+xml")
      expect(manifest_item("text/02_chapter_one.xhtml")["media-type"]).to eq("application/xhtml+xml")
      expect(manifest_item("css/book.css")["media-type"]).to eq("text/css")
      expect(manifest_item("js/book.js")["media-type"]).to eq("text/javascript")
      expect(manifest_item("bkr/bkr.js")["media-type"]).to eq("text/javascript")
      expect(manifest_item("images/cover.png")["properties"]).to eq("cover-image")
    end

    it "marks chapters that load scripts as scripted" do
      build

      expect(manifest_item("text/01_introduction.xhtml")["properties"].split).to include("scripted")
      expect(manifest_item("text/02_chapter_one.xhtml")["properties"].split).to include("scripted")
    end

    it "does not mark chapters as scripted when there are no scripts" do
      update_config(bkr_assets: false, scripts: [])
      build

      expect(manifest_item("text/01_introduction.xhtml")["properties"].to_s.split).not_to include("scripted")
      expect(entry_names.grep(/\.js\z/)).to be_empty
    end

    it "orders the spine like the config" do
      update_config(chapters: ["chapter_one.html", "introduction.html"])
      build

      expect(spine_hrefs).to eq(["text/01_chapter_one.xhtml", "text/02_introduction.xhtml"])
    end

    it "generates an EPUB 3 nav document listing the chapter titles in order" do
      build

      nav_item = opf.at_xpath("//opf:item[@properties='nav']", namespaces)
      expect(nav_item["href"]).to eq("nav.xhtml")
      expect(nav_titles).to eq([["Introduction", "text/01_introduction.xhtml"],
                                ["Chapter One", "text/02_chapter_one.xhtml"]])
    end

    it "also writes an NCX table of contents for EPUB 2 readers" do
      build

      expect(manifest_item("toc.ncx")["media-type"]).to eq("application/x-dtbncx+xml")
      expect(opf.at_xpath("//opf:spine", namespaces)["toc"]).to eq(manifest_item("toc.ncx")["id"])
    end

    it "titles chapters from the config, then the first h1, then h2, then the file name" do
      write_file("content/03_the_last_page.html", "<p>The end.</p>\n")
      write_file("content/both.html", "<h2>Second level</h2>\n<h1>First level</h1>\n")
      update_config(chapters: [{ "file" => "introduction.html", "title" => "Welcome" },
                               "introduction.html", "chapter_one.html", "both.html", "03_the_last_page.html"])
      build

      expect(nav_titles.map(&:first))
        .to eq(["Welcome", "Introduction", "A Humble Beginning", "First level", "The last page"])
      expect(chapter("text/03_chapter_one.xhtml").at_xpath("//x:title", namespaces).text).to eq("A Humble Beginning")
    end

    it "discovers content/*.html and *.xhtml sorted by file name when chapters are omitted" do
      write_file("content/appendix.xhtml", "<h1>Appendix</h1>\n")
      write_file("content/notes.txt", "not a chapter")
      update_config(chapters: nil)
      build

      expect(spine_hrefs).to eq(["text/01_appendix.xhtml", "text/02_chapter_one.xhtml", "text/03_introduction.xhtml"])
    end

    it "does not double the number prefix of files that already have one" do
      write_file("content/07_epilogue.html", "<h1>Epilogue</h1>\n")
      write_file("content/42.html", "<h1>Just a number</h1>\n")
      update_config(chapters: ["07_epilogue.html", "42.html"])
      build

      expect(spine_hrefs).to eq(["text/01_epilogue.xhtml", "text/02_42.xhtml"])
    end
  end

  describe "chapter documents" do
    it "wraps the fragment in a well-formed XHTML5 document" do
      build
      raw = read_entry("OEBPS/text/01_introduction.xhtml")
      doc = chapter("text/01_introduction.xhtml")

      expect(raw).to start_with(%(<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n))
      expect(doc.root.name).to eq("html")
      expect(doc.root.namespace.href).to eq("http://www.w3.org/1999/xhtml")
      expect([doc.root["lang"], doc.root.attribute_with_ns("lang", "http://www.w3.org/XML/1998/namespace")&.value])
        .to eq(%w[en en])
      expect(doc.at_xpath("//x:head/x:meta/@charset", namespaces).value).to eq("UTF-8")
      expect(doc.at_xpath("//x:body/x:h1", namespaces).text).to eq("Introduction")
    end

    it "links bundled assets first, then the author's stylesheets and scripts" do
      build
      doc = chapter("text/02_chapter_one.xhtml")

      expect(doc.xpath("//x:head/x:link[@rel='stylesheet']/@href", namespaces).map(&:value))
        .to eq(["../bkr/bkr.css", "../css/book.css"])
      expect(doc.xpath("//x:head/x:script/@src", namespaces).map(&:value)).to eq(["../bkr/bkr.js", "../js/book.js"])
      expect(read_entry("OEBPS/text/02_chapter_one.xhtml")).to include(%(<script src="../js/book.js"></script>))
    end

    it "omits the bundled assets when bkr_assets is false" do
      update_config(bkr_assets: false)
      build
      doc = chapter("text/01_introduction.xhtml")

      expect(doc.xpath("//x:head/x:link/@href", namespaces).map(&:value)).to eq(["../css/book.css"])
      expect(doc.xpath("//x:head/x:script/@src", namespaces).map(&:value)).to eq(["../js/book.js"])
      expect(entry_names.grep(%r{\AOEBPS/bkr/})).to be_empty
    end

    it "uses only the stylesheets and scripts listed in the config" do
      write_file("assets/css/extra.css", "p { color: red; }\n")
      write_file("assets/js/extra.js", "// extra\n")
      update_config(bkr_assets: false, stylesheets: ["css/extra.css"], scripts: [])
      build
      doc = chapter("text/01_introduction.xhtml")

      expect(doc.xpath("//x:head/x:link/@href", namespaces).map(&:value)).to eq(["../css/extra.css"])
      expect(doc.xpath("//x:head/x:script", namespaces)).to be_empty
      expect(entry_names).not_to include("OEBPS/css/book.css")
    end

    it "rewrites links to other chapters and to assets" do
      build
      doc = chapter("text/01_introduction.xhtml")

      expect(doc.at_xpath("//x:img/@src", namespaces).value).to eq("../images/cover.png")
      expect(doc.at_xpath("//x:a/@href", namespaces).value).to eq("02_chapter_one.xhtml#start")
    end

    it "keeps epub:type attributes and whitespace from the fragment" do
      build
      raw = read_entry("OEBPS/text/02_chapter_one.xhtml")

      expect(raw).to include(%(<section epub:type="chapter">\n  <h2 id="start">A Humble Beginning</h2>))
    end
  end

  describe "images and fonts" do
    it "adds every image and font with its EPUB core media type, skipping dotfiles" do
      %w[images/diagram.svg images/photos/beach.jpg images/anim.webp fonts/body.woff2 fonts/title.otf
         fonts/mono.ttf fonts/old.woff].each { |file| write_file("assets/#{file}", "x") }
      build

      expect(%w[images/diagram.svg images/photos/beach.jpg images/anim.webp].map { |h| manifest_item(h)["media-type"] })
        .to eq(%w[image/svg+xml image/jpeg image/webp])
      fonts = %w[fonts/body.woff2 fonts/title.otf fonts/mono.ttf fonts/old.woff]
      expect(fonts.map { |href| manifest_item(href)["media-type"] }).to eq(%w[font/woff2 font/otf font/ttf font/woff])
      expect(entry_names.grep(/\.keep\z/)).to be_empty
    end

    it "adds the cover only once and skips files with unsupported media types" do
      write_file("assets/images/readme.txt", "notes")
      build

      expect(opf.xpath("//opf:item[@href='images/cover.png']", namespaces).size).to eq(1)
      expect(entry_names).not_to include("OEBPS/images/readme.txt")
    end

    it "has no cover-image when no cover is configured" do
      update_config(cover: nil)
      build

      expect(opf.xpath("//opf:item[contains(@properties, 'cover-image')]", namespaces)).to be_empty
      expect(manifest_item("images/cover.png")).not_to be_nil
    end
  end

  describe "logging" do
    it "logs the major steps and every file added" do
      io = StringIO.new
      logger = Bkr::Logger.new(verbose: true, io: io)
      described_class.new(Bkr::Project.new(root, logger: logger)).build

      expect(io.string).to include("info  Building \"The Sample Book\"")
      expect(io.string).to include("debug  Adding text/01_introduction.xhtml from content/introduction.html")
      expect(io.string).to include("debug  Adding images/cover.png")
      expect(io.string).to include("info  Wrote build/sample_book.epub")
    end
  end

  describe "errors" do
    def expect_build_error(message)
      expect { build }.to raise_error(Bkr::BuildError, message)
    end

    it "reports a missing chapter file" do
      update_config(chapters: ["introduction.html", "missing.html"])
      expect_build_error(%r{Chapter file not found: content/missing\.html})
    end

    it "reports a book without chapters" do
      update_config(chapters: [])
      expect_build_error(/No chapters to build/)
    end

    it "reports an empty content folder when chapters are omitted" do
      FileUtils.rm(Dir.glob(File.join(root, "content", "*")))
      update_config(chapters: nil)
      expect_build_error(%r{No chapters to build\. Add \.html files to content/})
    end

    it "reports a missing cover" do
      update_config(cover: "images/nope.png")
      expect_build_error(%r{Cover image not found: assets/images/nope\.png})
    end

    it "reports a cover that is not an image" do
      update_config(cover: "css/book.css")
      expect_build_error(%r{Cover assets/css/book\.css must be a PNG, JPEG, GIF, SVG or WebP image})
    end

    it "reports a missing stylesheet" do
      update_config(stylesheets: ["css/missing.css"])
      expect_build_error(%r{File not found: assets/css/missing\.css \(listed under `stylesheets:`})
    end

    it "reports a missing script" do
      update_config(scripts: ["js/missing.js"])
      expect_build_error(%r{File not found: assets/js/missing\.js \(listed under `scripts:`})
    end

    it "reports a stylesheet that is not a .css file" do
      update_config(stylesheets: ["js/book.js"])
      expect_build_error(%r{assets/js/book\.js is listed under `stylesheets:` but is not a \.css file})
    end

    it "reports malformed chapter XHTML with the file and line" do
      write_file("content/chapter_one.html", "<h2>Fine</h2>\n<p>Broken <b>bold</p>\n")
      expect_build_error(
        %r{content/chapter_one\.html is not well-formed XHTML.*\n  content/chapter_one\.html:2:\d+: .*mismatch}m
      )
    end

    it "reports HTML entities that XML does not know" do
      write_file("content/introduction.html", "<p>a&nbsp;b</p>\n")
      expect_build_error(%r{content/introduction\.html:1:\d+: Entity 'nbsp' not defined})
    end

    it "rejects config paths that leave the project folders" do
      update_config(chapters: ["../config/book.yml"])
      expect_build_error(%r{`chapters:` entry "\.\./config/book\.yml" .* must be a relative path inside content/})
    end

    it "rejects absolute asset paths" do
      update_config(stylesheets: ["/etc/hosts"])
      expect_build_error(%r{`stylesheets:` entry "/etc/hosts" .* inside assets/})
    end

    it "rejects asset paths that climb out of assets/" do
      update_config(cover: "../../secret.png")
      expect_build_error(%r{`cover:` entry "\.\./\.\./secret\.png" .* inside assets/})
    end

    it "rejects home-relative paths" do
      update_config(scripts: ["~/evil.js"])
      expect_build_error(%r{`scripts:` entry "~/evil\.js"})
    end

    it "does not leave a partial epub behind" do
      update_config(chapters: ["missing.html"])
      expect { build }.to raise_error(Bkr::BuildError)
      expect(Dir.exist?(File.join(root, "build")) ? Dir.children(File.join(root, "build")) : []).to be_empty
    end
  end

  describe "EPUBCheck", :java do
    it "produces an EPUB that passes EPUBCheck" do
      result = Bkr::Validator.new(logger: Bkr::Logger.null).validate(build)

      expect(result.errors).to eq([])
      expect(result).to be_valid
    end
  end
end
