# frozen_string_literal: true

RSpec.describe Bkr::Logger do
  around { |example| in_tmpdir { example.run } }

  let(:io) { StringIO.new }
  let(:log_path) { File.join("tmp", "nested", "bkr.log") }

  it "creates the log folder" do
    described_class.new(log_path: log_path).close

    expect(File).to exist(log_path)
  end

  it "writes every level to the file with its severity" do
    logger = described_class.new(log_path: log_path)
    logger.debug("details")
    logger.info("building")
    logger.warn("careful")
    logger.error("broken")
    logger.close

    log = File.read(log_path)
    expect(log).to match(/^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] DEBUG details$/)
    expect(log).to include("INFO  building", "WARN  careful", "ERROR broken")
  end

  it "echoes to the io when verbose" do
    logger = described_class.new(log_path: log_path, verbose: true, io: io)
    logger.info("building")
    logger.debug("details")

    expect(io.string).to eq " info  building\ndebug  details\n"
  end

  it "does not echo when not verbose" do
    logger = described_class.new(log_path: log_path, io: io)
    logger.info("building")

    expect(io.string).to be_empty
  end

  it "returns nil from the log methods" do
    expect(described_class.new(verbose: true, io: io).info("x")).to be_nil
  end

  it "does not close the io on close" do
    logger = described_class.new(log_path: log_path, verbose: true, io: $stdout)
    logger.close

    expect($stdout).not_to be_closed
    expect { logger.info("still here") }.to output(/still here/).to_stdout_from_any_process
  end

  describe ".null" do
    it "discards everything" do
      logger = described_class.null

      expect { described_class::LEVELS.each { |level| logger.public_send(level, "x") } }
        .not_to output.to_stdout
      expect(logger.log_path).to be_nil
      expect { logger.close }.not_to raise_error
    end
  end
end
