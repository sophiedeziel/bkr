# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bkr::Cli do
  let(:valid_result) { Bkr::Validator::Result.new(errors: [], warnings: ["OPF-999: just a warning"]) }
  let(:invalid_result) { Bkr::Validator::Result.new(errors: ["RSC-005: broken (EPUB/x.xhtml:1:1)"], warnings: []) }

  def stub_validator(result)
    validator = instance_double(Bkr::Validator, validate: result)
    allow(Bkr::Validator).to receive(:new).and_return(validator)
    validator
  end

  describe "version" do
    it "prints the version" do
      out, = run_cli("version")
      expect(out).to include("bkr #{Bkr::VERSION}")
    end

    it "supports --version" do
      out, = run_cli("--version")
      expect(out).to include(Bkr::VERSION)
    end
  end

  describe "help" do
    it "lists every command" do
      out, = run_cli("help")
      expect(out).to include("book new NAME", "book build", "book validate")
    end
  end

  context "when outside a bkr project" do
    it "explains how to start one on build" do
      in_tmpdir do
        _, err = run_cli("build")
        expect(err).to include("No bkr project found", "book new NAME")
      end
    end

    it "explains how to start one on validate" do
      in_tmpdir do
        _, err = run_cli("validate")
        expect(err).to include("No bkr project found")
      end
    end
  end

  describe "new → build → validate" do
    around do |example|
      in_tmpdir do
        run_cli("new", "my_book")
        Dir.chdir("my_book") { example.run }
      end
    end

    it "builds the generated project into build/my_book.epub" do
      out, err = run_cli("build")
      expect(err).to be_empty
      expect(out).to include("build/my_book.epub")
      expect(File.size("build/my_book.epub")).to be > 0
    end

    it "builds from a nested directory of the project" do
      Dir.chdir("content") { run_cli("build") }
      expect(File).to exist("build/my_book.epub")
    end

    it "writes a log file in tmp/" do
      run_cli("build")
      expect(File.read("tmp/bkr.log")).to include("INFO")
    end

    it "prints build steps with --verbose" do
      out, = run_cli("build", "--verbose")
      expect(out.lines.size).to be > 2
    end

    it "validates after building with --validate" do
      validator = stub_validator(valid_result)
      out, err = run_cli("build", "--validate")
      expect(validator).to have_received(:validate).with(File.expand_path("build/my_book.epub"))
      expect(out).to include("valid", "OPF-999")
      expect(err).to be_empty
    end

    it "fails when the EPUB is invalid" do
      run_cli("build")
      stub_validator(invalid_result)
      out, err = run_cli("validate")
      expect(out).to include("RSC-005")
      expect(err).to include("is not a valid EPUB (1 error(s))")
    end

    it "asks to build first when there is no EPUB yet" do
      _, err = run_cli("validate")
      expect(err).to include("Run `book build` first")
    end

    it "validates an explicit EPUB path" do
      run_cli("build")
      validator = stub_validator(valid_result)
      run_cli("validate", "build/my_book.epub")
      expect(validator).to have_received(:validate).with(File.expand_path("build/my_book.epub"))
    end

    it "reports a missing Java runtime nicely" do
      run_cli("build")
      validator = instance_double(Bkr::Validator)
      allow(validator).to receive(:validate).and_raise(Bkr::JavaMissingError, "EPUBCheck needs Java")
      allow(Bkr::Validator).to receive(:new).and_return(validator)
      _, err = run_cli("validate")
      expect(err).to include("EPUBCheck needs Java")
    end

    it "reports config errors without a stack trace" do
      File.write("config/book.yml", "title: Only a title\n")
      _, err = run_cli("build")
      expect(err).to include("missing required key(s): author, language, identifier")
    end

    it "produces an EPUB that passes EPUBCheck", :java do
      run_cli("build")
      result = Bkr::Validator.new.validate(File.expand_path("build/my_book.epub"))
      expect(result.errors).to eq([])
    end
  end
end
