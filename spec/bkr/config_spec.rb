# frozen_string_literal: true

RSpec.describe Bkr::Config do
  let(:required) do
    { "title" => "My Book", "author" => "Jane Doe", "language" => "en", "identifier" => "urn:uuid:1234" }
  end

  def config_with(extra = {})
    described_class.new(required.merge(extra))
  end

  describe ".new" do
    it "reads the required metadata" do
      config = config_with

      expect([config.title, config.author, config.language, config.identifier])
        .to eq ["My Book", "Jane Doe", "en", "urn:uuid:1234"]
    end

    it "accepts symbol keys" do
      expect(described_class.new(required.transform_keys(&:to_sym)).title).to eq "My Book"
    end

    it "lists every missing required key in the error" do
      expect { described_class.new({ "title" => "My Book", "author" => " " }, path: "config/book.yml") }
        .to raise_error(Bkr::ConfigError, "config/book.yml is missing required key(s): author, language, identifier")
    end

    it "accepts a single author as a string" do
      config = config_with("author" => "Jane Doe")

      expect(config.authors).to eq ["Jane Doe"]
      expect(config.author).to eq "Jane Doe"
    end

    it "accepts a list of authors" do
      config = config_with("author" => ["Jane Doe", "John Roe"])

      expect(config.authors).to eq ["Jane Doe", "John Roe"]
      expect(config.author).to eq "Jane Doe"
    end

    it "rejects an empty author list" do
      expect { config_with("author" => []) }.to raise_error(Bkr::ConfigError, /author/)
    end

    it "leaves optional metadata nil when absent" do
      config = config_with

      expect([config.publisher, config.description, config.date, config.filename, config.cover]).to all(be_nil)
    end

    it "keeps dates as Date objects" do
      expect(config_with("date" => Date.new(2026, 11, 22)).date).to eq Date.new(2026, 11, 22)
    end

    describe "chapters" do
      it "is nil when not configured (use every content/*.html)" do
        expect(config_with.chapters).to be_nil
      end

      it "supports the short and long forms" do
        chapters = config_with("chapters" => ["intro.html", { "file" => "one.html", "title" => "One" },
                                              { file: "two.html" }]).chapters

        expect(chapters).to eq [
          described_class::Chapter.new(file: "intro.html", title: nil),
          described_class::Chapter.new(file: "one.html", title: "One"),
          described_class::Chapter.new(file: "two.html", title: nil)
        ]
      end

      it "must be a list" do
        expect { config_with("chapters" => "intro.html") }.to raise_error(Bkr::ConfigError, "chapters must be a list")
      end

      it "needs a file in the long form" do
        expect { config_with("chapters" => [{ "title" => "One" }]) }
          .to raise_error(Bkr::ConfigError, /each chapter needs a file/)
      end

      it "rejects other kinds of entries" do
        expect { config_with("chapters" => [42]) }.to raise_error(Bkr::ConfigError, "invalid chapter entry: 42")
      end
    end

    describe "stylesheets and scripts" do
      it "are nil when not configured (use the defaults)" do
        config = config_with

        expect(config.stylesheets).to be_nil
        expect(config.scripts).to be_nil
      end

      it "are exactly the configured list otherwise" do
        config = config_with("stylesheets" => "css/book.css", "scripts" => ["js/a.js", "js/b.js"])

        expect(config.stylesheets).to eq ["css/book.css"]
        expect(config.scripts).to eq ["js/a.js", "js/b.js"]
      end

      it "can be configured as empty" do
        config = config_with("stylesheets" => [], "scripts" => nil)

        expect(config.stylesheets).to eq []
        expect(config.scripts).to eq []
      end
    end

    describe "bkr_assets" do
      it "defaults to true" do
        expect(config_with).to be_bkr_assets
      end

      it "can be turned off" do
        expect(config_with("bkr_assets" => false)).not_to be_bkr_assets
      end
    end
  end

  describe "filename" do
    it "accepts a plain name and drops a trailing .epub" do
      expect(config_with("filename" => "my_book.epub").filename).to eq "my_book"
    end

    ["../../outside", "nested/name", "..\\evil", ".hidden", " "].each do |bad|
      it "rejects #{bad.inspect}" do
        expect { config_with("filename" => bad) }.to raise_error(Bkr::ConfigError, /plain file name/)
      end
    end
  end

  describe ".load" do
    around { |example| in_tmpdir { example.run } }

    def write_config(yaml)
      File.write("book.yml", yaml)
      "book.yml"
    end

    it "loads a YAML file and parses dates" do
      config = described_class.load(write_config(<<~YAML))
        title: My Book
        author: [Jane Doe, John Roe]
        language: en
        identifier: urn:uuid:1234
        date: 2026-11-22
        chapters:
          - intro.html
          - file: one.html
            title: One
      YAML

      expect(config.path).to eq "book.yml"
      expect(config.authors).to eq ["Jane Doe", "John Roe"]
      expect(config.date).to eq Date.new(2026, 11, 22)
      expect(config.chapters.map(&:file)).to eq ["intro.html", "one.html"]
    end

    it "raises ConfigError when the file is missing" do
      expect { described_class.load("missing.yml") }
        .to raise_error(Bkr::ConfigError, "Config file not found: missing.yml")
    end

    it "raises ConfigError for invalid YAML" do
      expect { described_class.load(write_config("title: [unclosed\n")) }
        .to raise_error(Bkr::ConfigError, /book\.yml is not valid YAML/)
    end

    it "raises ConfigError when the YAML is not a mapping" do
      expect { described_class.load(write_config("- just\n- a list\n")) }
        .to raise_error(Bkr::ConfigError, "book.yml must contain a YAML mapping (key: value pairs)")
    end

    it "raises ConfigError listing every required key for an empty file" do
      expect { described_class.load(write_config("")) }
        .to raise_error(Bkr::ConfigError, /missing required key\(s\): title, author, language, identifier/)
    end

    it "raises ConfigError for YAML that safe_load refuses (aliases, Ruby objects)" do
      expect { described_class.load(write_config("base: &base x\ntitle: *base\n")) }.to raise_error(Bkr::ConfigError)
    end
  end
end
