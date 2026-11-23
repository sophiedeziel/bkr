# frozen_string_literal: true

require "zip"

RSpec.describe Bkr::Validator do
  subject(:validator) { described_class.new(logger: Bkr::Logger.new(verbose: true, io: log_io), runner: runner) }

  let(:log_io) { StringIO.new }
  let(:commands) { [] }
  let(:epub_path) { File.join(Dir.pwd, "book.epub") }
  let(:runner) { fake_runner(report: File.read(fixture_path("epubcheck", "valid_report.json"))) }

  around do |example|
    in_tmpdir do
      File.write("book.epub", "not really an epub")
      example.run
    end
  end

  def status(code)
    instance_double(Process::Status, success?: code.zero?, exitstatus: code)
  end

  def java_ok
    ["", "openjdk version \"21.0.2\" 2024-01-16\nOpenJDK Runtime Environment\n", status(0)]
  end

  # Mimics Open3.capture3: answers `java -version`, and for the EPUBCheck run
  # writes `report` (if any) where --json points and returns `epubcheck`.
  def fake_runner(report: nil, java: java_ok, epubcheck: ["", "", status(0)])
    lambda do |*argv|
      commands << argv
      next java if argv == %w[java -version]

      File.write(argv[argv.index("--json") + 1], report) if report
      epubcheck
    end
  end

  describe "#validate" do
    it "raises Bkr::Error without running anything when the EPUB does not exist" do
      expect { validator.validate("nope.epub") }.to raise_error(Bkr::Error, /No EPUB at .*nope\.epub/)
      expect(commands).to be_empty
    end

    it "runs the bundled EPUBCheck jar with a JSON report, as an argv array" do
      validator.validate("book.epub")

      expect(commands.first).to eq(%w[java -version])
      java, jar_flag, jar, epub, json_flag, report_path = commands.last
      expect([java, jar_flag, jar, epub, json_flag])
        .to eq(["java", "-jar", described_class::JAR_FILE, epub_path, "--json"])
      expect(report_path).to end_with("report.json")
      expect(File).not_to exist(report_path)
    end

    it "logs what it does" do
      validator.validate("book.epub")

      expect(log_io.string).to include("info  Validating #{epub_path} with EPUBCheck 5.3")
      expect(log_io.string).to include("debug  Running: java -jar #{described_class::JAR_FILE}")
      expect(log_io.string).to include("info  EPUBCheck: no errors, 0 warning(s)")
    end

    context "when Java is missing" do
      it "raises JavaMissingError when `java -version` fails (macOS stub)" do
        stub = ["", "The operation couldn’t be completed. Unable to locate a Java Runtime.\n", status(1)]
        validator = described_class.new(runner: fake_runner(java: stub))

        expect { validator.validate("book.epub") }
          .to raise_error(Bkr::JavaMissingError, /Java 11 or newer.*brew install openjdk.*adoptium\.net/m)
      end

      it "raises JavaMissingError when the java executable does not exist" do
        validator = described_class.new(runner: ->(*) { raise Errno::ENOENT, "java" })

        expect { validator.validate("book.epub") }.to raise_error(Bkr::JavaMissingError, /`java` was not found/)
      end

      it "raises JavaMissingError when Java is older than 11" do
        old_java = ["", "java version \"1.8.0_391\"\n", status(0)]
        validator = described_class.new(runner: fake_runner(java: old_java))

        expect { validator.validate("book.epub") }.to raise_error(Bkr::JavaMissingError, /Java 8 is installed/)
      end
    end

    context "with a report containing problems" do
      let(:runner) do
        fake_runner(report: File.read(fixture_path("epubcheck", "report_with_problems.json")),
                    epubcheck: ["", "", status(1)])
      end

      it "turns FATAL and ERROR messages into errors, one per message with all its locations" do
        expect(validator.validate("book.epub").errors).to eq [
          'PKG-008: Unable to read file "EPUB/missing.xhtml". (EPUB/package.opf)',
          'RSC-005: Error while parsing file: element "p" not allowed here. ' \
          "(EPUB/text/ch1.xhtml:12:4, EPUB/text/ch2.xhtml:3:10)",
          'RSC-007: Referenced resource "images/cover.png" could not be found in the EPUB. ' \
          "(EPUB/nav.xhtml:8, and 12 more)"
        ]
      end

      it "turns WARNING messages into warnings" do
        result = validator.validate("book.epub")

        expect(result.warnings).to eq [
          'OPF-053: Date value "2026-13-01" does not follow recommended syntax as per ' \
          "http://www.w3.org/TR/NOTE-datetime. (EPUB/package.opf:7:32)"
        ]
        expect(result).not_to be_valid
      end

      it "only logs USAGE and INFO messages at debug level" do
        result = validator.validate("book.epub")

        expect((result.errors + result.warnings).join).not_to include("HTM-010", "INF-001")
        expect(log_io.string).to include("debug  EPUBCheck USAGE: HTM-010", "debug  EPUBCheck INFO: INF-001")
        expect(log_io.string).to include("info  EPUBCheck: 3 error(s), 1 warning(s)")
      end
    end

    context "with a clean report" do
      it "is valid" do
        result = validator.validate("book.epub")

        expect(result).to be_valid
        expect(result.errors).to be_empty
        expect(result.warnings).to be_empty
      end
    end

    context "when EPUBCheck crashes without writing a report" do
      it "uses ERROR/FATAL lines from its output as errors" do
        stderr = "Exception in thread \"main\" java.lang.OutOfMemoryError\nERROR: boom\nFATAL(RSC-001): gone\n"
        validator = described_class.new(runner: fake_runner(epubcheck: ["Check started\n", stderr, status(1)]))

        expect(validator.validate("book.epub").errors).to eq ["ERROR: boom", "FATAL(RSC-001): gone"]
      end

      it "reports the exit status when the output has nothing useful" do
        validator = described_class.new(runner: fake_runner(epubcheck: ["", "Killed\n", status(137)]))

        expect(validator.validate("book.epub").errors)
          .to eq ["EPUBCheck failed (exit status 137) without producing a report"]
      end

      it "falls back the same way when the report is not valid JSON" do
        validator = described_class.new(runner: fake_runner(report: "{\"messages\": [", epubcheck: ["", "", status(2)]))

        expect(validator.validate("book.epub")).not_to be_valid
      end
    end
  end

  describe "with the real EPUBCheck", :java do
    # Zips spec/fixtures/epubcheck/minimal_epub with the mimetype entry first and stored.
    # EPUBCheck rejects a mimetype entry with ZIP extra fields, which rubyzip 3
    # adds by default (Zip64), hence suppress_extra_fields.
    def write_minimal_epub(path)
      source = fixture_path("epubcheck", "minimal_epub")
      Zip::OutputStream.open(path, suppress_extra_fields: true) do |zip|
        zip.put_next_entry("mimetype", nil, nil, Zip::Entry::STORED)
        zip.write("application/epub+zip")
        Dir.glob("**/*", base: source).sort.each do |name|
          next if File.directory?(File.join(source, name))

          zip.put_next_entry(name)
          zip.write(File.read(File.join(source, name)))
        end
      end
    end

    it "validates a minimal hand-made EPUB 3" do
      write_minimal_epub("minimal.epub")

      result = described_class.new.validate("minimal.epub")

      expect(result.errors).to eq []
      expect(result).to be_valid
    end
  end
end
