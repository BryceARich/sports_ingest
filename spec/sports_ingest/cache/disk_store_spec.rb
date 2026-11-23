# frozen_string_literal: true

require "tmpdir"

RSpec.describe SportsIngest::Cache::DiskStore do
  subject(:store) { described_class.new(dir) }

  let(:tmp) { Dir.mktmpdir }
  let(:dir) { File.join(tmp, "raw") }

  after { FileUtils.rm_rf(tmp) }

  it "writes and reads entries as JSON files" do
    store.write("nhl/ab/abc", {"status" => 200})

    expect(store.read("nhl/ab/abc")).to eq({"status" => 200})
    expect(File.read(File.join(dir, "nhl/ab/abc.json"))).to eq('{"status":200}')
  end

  it "creates files readable by the owner only" do
    store.write("nhl/abc", {})

    expect(File.stat(File.join(dir, "nhl/abc.json")).mode & 0o777).to eq(0o600)
  end

  it "reads a missing or unparseable file as a miss" do
    expect(store.read("nhl/none")).to be_nil

    FileUtils.mkdir_p(File.join(dir, "nhl"))
    File.write(File.join(dir, "nhl/bad.json"), "{not json")
    expect(store.read("nhl/bad")).to be_nil
  end

  it "deletes and clears" do
    store.write("nhl/a", {})
    store.write("nhl/b", {})
    store.delete("nhl/a")
    expect(store.read("nhl/a")).to be_nil

    store.clear
    expect(store.read("nhl/b")).to be_nil
  end

  it "rejects keys that could leave the directory" do
    expect { store.read("../etc/passwd") }.to raise_error(SportsIngest::ConfigurationError)
    expect { store.write("/abs", {}) }.to raise_error(SportsIngest::ConfigurationError)
  end

  it "raises the gem's Error when it can't write" do
    File.write(tmp + "/raw", "a file, not a directory")

    expect { store.write("nhl/a", {}) }.to raise_error(SportsIngest::Error, /can't write cache file/)
  end
end
