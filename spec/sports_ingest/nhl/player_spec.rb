# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Player do
  subject(:player) do
    described_class.new(ref: {sport: :hockey, canonical_id: 8_478_402}, first_name: "Connor",
      last_name: "McDavid", position: "C", team: "EDM", sweater_number: 97, shoots_catches: "L",
      height_inches: 73, weight_pounds: 194, birth_date: "1997-01-13", birth_city: "Richmond Hill",
      birth_state_province: "ON", birth_country: "CAN", headshot: nil)
  end

  it "exposes the NHL id, full name and position helpers" do
    expect(player.id).to eq("8478402")
    expect(player.full_name).to eq("Connor McDavid")
    expect(player).to be_forward
    expect(player).not_to be_defense
    expect(player).not_to be_goalie
  end

  it "parses the birth date" do
    expect(player.birth_date).to eq(Date.new(1997, 1, 13))
  end

  it "round-trips through JSON" do
    expect(described_class.from_h(JSON.parse(player.to_json))).to eq(player)
  end

  it "rejects an unknown position" do
    expect { player.with(position: "F") }.to raise_error(ArgumentError, /position/)
  end

  it "rejects a bad birth date" do
    expect { player.with(birth_date: "13/01/1997") }.to raise_error(ArgumentError, /ISO 8601/)
  end

  it "rejects a football ref" do
    expect { player.with(ref: {sport: :football, canonical_id: "00-0033873"}) }
      .to raise_error(ArgumentError, /hockey/)
  end
end
