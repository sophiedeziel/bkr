# frozen_string_literal: true

RSpec.describe Bkr::Project do
  around { |example| in_tmpdir { example.run } }

  let(:root) { File.join(Dir.pwd, "my_book") }

  def create_project(yaml = "title: T\nauthor: A\nlanguage: en\nidentifier: x\n")
    FileUtils.mkdir_p(File.join(root, "config"))
    FileUtils.mkdir_p(File.join(root, "content", "part1"))
    File.write(File.join(root, "config", "book.yml"), yaml)
  end

  describe ".find" do
    it "finds the project from its root" do
      create_project

      expect(described_class.find(root).root).to eq root
    end

    it "finds the project from a nested folder" do
      create_project

      expect(described_class.find(File.join(root, "content", "part1")).root).to eq root
    end

    it "defaults to the current directory" do
      create_project
      Dir.chdir(File.join(root, "content")) do
        expect(described_class.find.root).to eq root
      end
    end

    it "passes options through to the project" do
      create_project
      logger = Bkr::Logger.null

      expect(described_class.find(root, logger: logger).logger).to be logger
    end

    it "raises ProjectNotFoundError when there is no config/book.yml up the tree" do
      FileUtils.mkdir_p(root)

      expect { described_class.find(root) }
        .to raise_error(Bkr::ProjectNotFoundError,
                        %r{\ANo bkr project found \(looked for config/book\.yml in #{Regexp.escape(root)} and its})
    end
  end

  describe "paths" do
    subject(:project) { described_class.new(root) }

    it "derives every folder from the root" do
      expect(project).to have_attributes(
        config_path: File.join(root, "config", "book.yml"),
        content_dir: File.join(root, "content"),
        assets_dir: File.join(root, "assets"),
        build_dir: File.join(root, "build"),
        tmp_dir: File.join(root, "tmp"),
        log_path: File.join(root, "tmp", "bkr.log")
      )
    end

    it "expands a relative root" do
      Dir.chdir(File.dirname(root)) do
        expect(described_class.new("my_book").root).to eq File.join(Dir.pwd, "my_book")
      end
    end

    it "names the EPUB after the folder by default" do
      create_project

      expect(project.epub_path).to eq File.join(root, "build", "my_book.epub")
    end

    it "names the EPUB after the configured filename" do
      create_project("title: T\nauthor: A\nlanguage: en\nidentifier: x\nfilename: the_book\n")

      expect(project.epub_path).to eq File.join(root, "build", "the_book.epub")
    end

    it "loads its config lazily" do
      create_project

      expect(project.config.title).to eq "T"
    end

    it "logs to tmp/bkr.log by default" do
      create_project
      project.logger.info("hello")
      project.logger.close

      expect(File.read(project.log_path)).to include("INFO  hello")
    end
  end
end
