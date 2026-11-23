# frozen_string_literal: true

RSpec.describe SportsIngest::Cache::MemoryStore do
  subject(:store) { described_class.new }

  it "keeps a frozen JSON copy of each entry" do
    entry = {"status" => 200, "headers" => {"a" => "b"}}
    store.write("k", entry)
    entry["status"] = 500

    expect(store.read("k")).to eq({"status" => 200, "headers" => {"a" => "b"}})
    expect(store.read("k")["headers"]).to be_frozen
  end

  it "deletes and clears" do
    store.write("a", {})
    store.write("b", {})
    store.delete("a")
    expect(store.read("a")).to be_nil
    expect(store.keys).to eq(["b"])

    store.clear
    expect(store.read("b")).to be_nil
  end
end

RSpec.describe SportsIngest::Cache::NullStore do
  it "remembers nothing" do
    store = described_class.new
    store.write("k", {"x" => 1})

    expect(store.read("k")).to be_nil
    expect(store.keys).to eq([])
  end
end
