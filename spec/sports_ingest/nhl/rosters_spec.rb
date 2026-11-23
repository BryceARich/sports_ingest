# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Rosters do
  subject(:rosters) { described_class.new(client: client, processed: processed) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:client) { SportsIngest::NHL::Client.new(http: http) }
  let(:processed) { SportsIngest::Cache::Processed.new(store: SportsIngest::Cache::MemoryStore.new) }
  let(:base) { "https://api-web.nhle.com/v1/roster" }
  let(:json) { {"Content-Type" => "application/json"} }

  def row(id: 8_478_402, first: "Connor", last: "McDavid", position: "C", **extra)
    {"id" => id, "firstName" => {"default" => first}, "lastName" => {"default" => last},
     "positionCode" => position, "birthDate" => "1997-01-13"}.merge(extra)
  end

  def stub_roster(path, body, status: 200)
    stub_request(:get, "#{base}/#{path}").to_return(status: status, headers: json, body: body.to_json)
  end

  context "with a recorded roster", vcr: {cassette_name: "nhl/roster_edm_20252026"} do
    let(:players) { rosters.fetch("EDM", season: 2025) }

    it "returns Player models with NHL ids, position and birth date" do
      expect(players).not_to be_empty
      expect(players).to all(be_a(SportsIngest::NHL::Player))
      players.each do |player|
        expect(player.id).to match(/\A\d+\z/)
        expect(player.ref.source_id(:nhl)).to eq(player.id)
        expect(SportsIngest::NHL::Player::POSITIONS).to include(player.position)
        expect(player.birth_date).to be_a(Date)
        expect(player.team).to eq("EDM")
      end
    end

    it "lists forwards, then defensemen, then goalies" do
      groups = players.map { |p| (p.forward? && 0) || (p.defense? && 1) || 2 }
      expect(groups).to eq(groups.sort)
      expect(players.count(&:goalie?)).to be >= 1
    end

    it "saves the roster to the processed cache" do
      players
      entry = processed.read("nhl/rosters/EDM/20252026", model: SportsIngest::NHL::Player)

      expect(entry.models).to eq(players)
      expect(entry.source).to eq(:nhl)
    end
  end

  describe "#fetch" do
    it "asks for the current roster when no season is given" do
      stub_roster("TBL/current", {"forwards" => [row], "defensemen" => [], "goalies" => []})

      expect(rosters.fetch("T.B").map(&:full_name)).to eq(["Connor McDavid"])
      expect(processed.read("nhl/rosters/TBL/current", model: SportsIngest::NHL::Player)).not_to be_nil
    end

    it "accepts a Team" do
      stub_roster("EDM/20242025", {"forwards" => [], "defensemen" => [row(position: "D")], "goalies" => []})

      expect(rosters.fetch(SportsIngest::Teams.fetch("EDM"), season: 2024).first).to be_defense
    end

    it "returns an empty roster when the NHL sends {}" do
      stub_roster("EDM/19171918", {})

      expect(rosters.fetch("EDM", season: 1917)).to eq([])
    end

    it "works without a processed cache" do
      stub_roster("EDM/current", {"forwards" => [row], "defensemen" => [], "goalies" => []})

      expect(described_class.new(client: client, processed: nil).fetch("EDM").size).to eq(1)
    end

    it "raises NotFound for an unknown team code" do
      expect { rosters.fetch("XYZ") }.to raise_error(SportsIngest::NotFound)
    end

    it "raises NotFound when the NHL answers 404" do
      stub_request(:get, "#{base}/EDM/current").to_return(status: 404, body: "<html>Not Found</html>")

      expect { rosters.fetch("EDM") }.to raise_error(SportsIngest::NotFound)
    end

    it "rejects a season that isn't a start year" do
      expect { rosters.fetch("EDM", season: "2025") }.to raise_error(ArgumentError, /start year/)
    end
  end

  describe "#parse" do
    it "keeps optional bio fields nil when the NHL leaves them out" do
      player = rosters.parse({"forwards" => [row], "defensemen" => [], "goalies" => []}).first

      expect(player).to have_attributes(sweater_number: nil, birth_state_province: nil, team: nil,
        birth_date: Date.new(1997, 1, 13))
    end

    it "takes the default spelling of localized names" do
      payload = {"forwards" => [], "defensemen" => [],
                 "goalies" => [row(first: "Jiří", position: "G").merge("birthCity" => {"default" => "Plzeň", "cs" => "Plzeň"})]}

      expect(rosters.parse(payload).first).to have_attributes(first_name: "Jiří", birth_city: "Plzeň")
    end

    it "raises SourceChangedError when a group is missing" do
      expect { rosters.parse({"forwards" => []}) }
        .to raise_error(SportsIngest::SourceChangedError, /no "defensemen"/)
    end

    it "raises SourceChangedError for a player the model rejects" do
      payload = {"forwards" => [row(position: "W")], "defensemen" => [], "goalies" => []}

      expect { rosters.parse(payload) }.to raise_error(SportsIngest::SourceChangedError, /8478402.*position/)
    end

    it "raises SourceChangedError when the payload isn't an object" do
      expect { rosters.parse([]) }.to raise_error(SportsIngest::SourceChangedError)
    end
  end
end
