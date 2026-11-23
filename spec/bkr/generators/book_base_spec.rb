# frozen_string_literal: true

require "nokogiri"

RSpec.describe Bkr::Generators::BookBase do
  let(:expected_files) do
    %w[
      .gitignore
      README.md
      config/book.yml
      content/01_introduction.html
      content/02_interactive.html
      assets/css/book.css
      assets/js/.keep
      assets/images/.keep
      assets/fonts/.keep
      build/.keep
      tmp/.keep
    ]
  end

  # Runs the block with a git config that only knows about `name` (or no user at all).
  def with_git_user(name, &block)
    Dir.mktmpdir("bkr-git") do |dir|
      config = File.join(dir, "gitconfig")
      quoted = name.to_s.gsub(/[\\"]/) { |char| "\\#{char}" }
      File.write(config, name ? "[user]\n\tname = \"#{quoted}\"\n" : "")
      with_env("GIT_CONFIG_GLOBAL" => config, "GIT_CONFIG_NOSYSTEM" => "1", &block)
    end
  end

  def with_env(vars)
    previous = vars.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  describe "book new NAME" do
    it "creates the project layout" do
      in_tmpdir do
        with_git_user("Ada Lovelace") { run_cli("new", "my_book") }

        expected_files.each do |file|
          expect(File).to exist(File.join("my_book", file)), "expected my_book/#{file} to exist"
        end
      end
    end

    it "does not copy template-only files" do
      in_tmpdir do
        with_git_user("Ada Lovelace") { run_cli("new", "my_book") }

        files = Dir.glob("**/*", File::FNM_DOTMATCH, base: "my_book").reject { |f| File.directory?("my_book/#{f}") }
        expect(files).to match_array(expected_files)
      end
    end

    it "ignores built EPUBs and tmp/ in the generated .gitignore" do
      in_tmpdir do
        with_git_user("Ada Lovelace") { run_cli("new", "my_book") }

        expect(File.read("my_book/.gitignore")).to include("build/*.epub", "tmp/")
      end
    end

    it "prints the next steps" do
      in_tmpdir do
        out, = with_git_user("Ada Lovelace") { run_cli("new", "my_book") }

        expect(out).to include("cd my_book", "book build")
      end
    end

    describe "config/book.yml" do
      def generated_config_for(dir)
        Bkr::Config.load(File.join(dir, "config", "book.yml"))
      end

      def generated_config
        generated_config_for("my_book")
      end

      it "loads with the metadata derived from the name and git" do
        in_tmpdir do
          with_git_user("Ada Lovelace") { run_cli("new", "my_book") }
          config = generated_config

          expect(config.title).to eq("My Book")
          expect(config.author).to eq("Ada Lovelace")
          expect(config.language).to eq("en")
          expect(config.identifier).to match(/\Aurn:uuid:\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
          expect(config.date).to eq(Date.today)
          expect(config.bkr_assets?).to be(true)
        end
      end

      it "lists both chapters, and their files exist" do
        in_tmpdir do
          with_git_user("Ada Lovelace") { run_cli("new", "my_book") }
          chapters = generated_config.chapters

          expect(chapters.map(&:file)).to eq(%w[01_introduction.html 02_interactive.html])
          expect(chapters.map(&:title)).to all(be_a(String))
          chapters.each { |chapter| expect(File).to exist(File.join("my_book", "content", chapter.file)) }
        end
      end

      it "gives each book its own identifier" do
        in_tmpdir do
          with_git_user("Ada Lovelace") do
            run_cli("new", "one")
            run_cli("new", "two")
          end
          ids = %w[one two].map { |dir| Bkr::Config.load(File.join(dir, "config", "book.yml")).identifier }

          expect(ids.uniq.size).to eq(2)
        end
      end

      it "quotes names that would otherwise break the YAML" do
        in_tmpdir do
          with_git_user("O'Brien: \"The\" #1") { run_cli("new", "my-great_book") }
          config = generated_config_for("my-great_book")

          expect(config.title).to eq("My Great Book")
          expect(config.author).to eq("O'Brien: \"The\" #1")
        end
      end

      it "falls back to a default author when git has no user.name" do
        in_tmpdir do
          with_git_user(nil) { run_cli("new", "my_book") }

          expect(generated_config.author).to eq("Unknown Author")
        end
      end

      it "falls back to a default author when git is not installed" do
        in_tmpdir do
          with_env("PATH" => "") { run_cli("new", "my_book") }

          expect(generated_config.author).to eq("Unknown Author")
        end
      end
    end

    it "writes sample chapters that are well-formed XHTML fragments starting with an <h1>" do
      in_tmpdir do
        with_git_user("Ada Lovelace") { run_cli("new", "my_book") }

        Dir.glob("my_book/content/*.html").each do |path|
          xml = "<body xmlns=\"http://www.w3.org/1999/xhtml\">#{File.read(path)}</body>"
          document = Nokogiri::XML(xml, &:strict)
          first_element = document.root.element_children.first

          expect(first_element.name).to eq("h1"), "#{path} should start with an <h1>"
        end
      end
    end

    it "demonstrates every bundled widget in the interactive chapter" do
      in_tmpdir do
        with_git_user("Ada Lovelace") { run_cli("new", "my_book") }
        chapter = File.read("my_book/content/02_interactive.html")

        %w[reveal quiz steps].each { |widget| expect(chapter).to include("data-bkr=\"#{widget}\"") }
      end
    end

    it "accepts an existing empty folder" do
      in_tmpdir do
        Dir.mkdir("my_book")
        with_git_user("Ada Lovelace") { run_cli("new", "my_book") }

        expect(File).to exist("my_book/config/book.yml")
      end
    end

    it "refuses to write into a non-empty folder" do
      in_tmpdir do
        Dir.mkdir("my_book")
        File.write("my_book/notes.txt", "keep me")
        _, err = with_git_user("Ada Lovelace") { run_cli("new", "my_book") }

        expect(err).to include("my_book already exists and is not empty")
        expect(File).not_to exist("my_book/config/book.yml")
        expect(File.read("my_book/notes.txt")).to eq("keep me")
      end
    end

    it "refuses when NAME is an existing file" do
      in_tmpdir do
        File.write("my_book", "")
        _, err = with_git_user("Ada Lovelace") { run_cli("new", "my_book") }

        expect(err).to include("is not a directory")
      end
    end
  end

  describe "bundled assets" do
    it "ships bkr.css and bkr.js" do
      expect(File).to exist(File.join(Bkr::ASSETS_DIR, "bkr.css"))
      expect(File).to exist(File.join(Bkr::ASSETS_DIR, "bkr.js"))
    end

    it "keeps bkr.js free of network access, eval and innerHTML" do
      script = File.read(File.join(Bkr::ASSETS_DIR, "bkr.js"))

      expect(script).not_to match(/\b(eval|innerHTML|XMLHttpRequest|fetch)\b/)
    end

    it "keeps bkr.css free of external resources" do
      css = File.read(File.join(Bkr::ASSETS_DIR, "bkr.css"))

      expect(css).not_to match(/@import|url\(/)
    end
  end
end
