# frozen_string_literal: true

require "sports_ingest/espn"

RSpec.describe SportsIngest::ESPN::LineupSlots do
  it "names slots per sport" do
    expect(described_class.name_for(:football, 23)).to eq("FLEX")
    expect(described_class.name_for(:ffl, "16")).to eq("D/ST")
    expect(described_class.name_for(:hockey, 3)).to eq("F")
  end

  it "names unknown slots by ID" do
    expect(described_class.name_for(:hockey, 42)).to eq("slot_42")
  end

  it "rejects an ID that isn't an integer" do
    expect { described_class.name_for(:hockey, "F") }.to raise_error(ArgumentError)
  end
end
