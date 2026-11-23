# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bkr do
  it "has a version number" do
    expect(Bkr::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "ships its bundled assets" do
    expect(Dir.exist?(Bkr::ASSETS_DIR)).to be(true)
  end
end
