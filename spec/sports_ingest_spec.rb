# frozen_string_literal: true

RSpec.describe SportsIngest do
  it "has a semantic version number" do
    expect(SportsIngest::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "autoloads its files with Zeitwerk" do
    expect(described_class.loader).to be_a(Zeitwerk::Loader)
  end

  it "maps every file under lib/ to the constant its path names" do
    expect { described_class.loader.eager_load(force: true) }.not_to raise_error
  end
end
