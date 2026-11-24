# frozen_string_literal: true

require "sports_ingest/espn"

RSpec.describe SportsIngest::ESPN::Read::Client do
  subject(:espn) { described_class.new(game: :hockey, http: http, configuration: config) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:limiter) { SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}) }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :espn, rate_limiter: limiter, max_retries: 0, configuration: config)
  end
  let(:base) { "https://lm-api-reads.fantasy.espn.com/apis/v3/games/fhl" }
  let(:league_url) { "#{base}/seasons/2027/segments/0/leagues/12345" }
  let(:json) { {"Content-Type" => "application/json;charset=utf-8"} }
  let(:unauthorized) do
    {status: 401, headers: json,
     body: '{"messages":["You are not authorized to view this League."],"details":[{"type":"AUTH_LEAGUE_NOT_VISIBLE"}]}'}
  end

  def with_cookies
    config.espn_s2 = "s2-value"
    config.espn_swid = "{SWID-VALUE}"
  end

  describe ".new" do
    it "maps game names to ESPN's segment" do
      expect(described_class.new(game: :football, http: http).game).to eq("ffl")
      expect(described_class.new(game: "FHL", http: http).game).to eq("fhl")
    end

    it "rejects an unknown game" do
      expect { described_class.new(game: :curling) }.to raise_error(ArgumentError, /game must be one of/)
    end

    it "goes through the raw cache by default" do
      stub_request(:get, "#{base}/seasons/2027").to_return(status: 200, headers: json, body: '{"id":2027}')
      config.raw_cache = :memory
      cached = described_class.new(game: :fhl, configuration: config)

      2.times { cached.season(2027) }

      expect(a_request(:get, "#{base}/seasons/2027")).to have_been_made.once
    end
  end

  describe "#url_for" do
    it "adds views as repeated view parameters, in order" do
      expect(espn.url_for("/seasons/2027", %w[mTeam mRoster]))
        .to eq("#{base}/seasons/2027?view=mTeam&view=mRoster")
    end

    it "leaves the query off without views" do
      expect(espn.url_for("seasons/2027")).to eq("#{base}/seasons/2027")
    end
  end

  describe "#league" do
    it "fetches a private league with the cookies" do
      with_cookies
      stub_request(:get, "#{league_url}?view=mSettings")
        .with(headers: {"Cookie" => "espn_s2=s2-value; SWID={SWID-VALUE}"})
        .to_return(status: 200, headers: json, body: '{"id":12345,"settings":{"name":"Spec League"}}')

      league = espn.league(12_345, season: 2027, views: ["mSettings"])

      expect(league.dig("settings", "name")).to eq("Spec League")
    end

    it "raises AuthError naming the missing cookies when a private league is fetched without them" do
      stub_request(:get, "#{league_url}?view=mSettings").to_return(unauthorized)

      expect { espn.league(12_345, season: 2027, views: ["mSettings"]) }
        .to raise_error(SportsIngest::AuthError, /missing: espn_s2, SWID.*SPORTS_INGEST_ESPN_S2/) { |e|
          expect(e.source).to eq(:espn)
        }
      expect(a_request(:get, "#{league_url}?view=mSettings").with { |r| !r.headers.key?("Cookie") })
        .to have_been_made
    end

    it "sends no cookie when only one of the two is set" do
      config.espn_s2 = "s2-value"
      stub_request(:get, league_url).to_return(unauthorized)

      expect { espn.league(12_345, season: 2027) }.to raise_error(SportsIngest::AuthError, /missing: SWID\)/)
      expect(a_request(:get, league_url).with { |r| !r.headers.key?("Cookie") }).to have_been_made
    end

    it "says the cookies may have expired when ESPN rejects them" do
      with_cookies
      stub_request(:get, league_url).to_return(unauthorized)

      expect { espn.league(12_345, season: 2027) }.to raise_error(SportsIngest::AuthError, /may have expired/) { |e|
        expect(e.message).not_to include("s2-value")
      }
    end

    it "raises NotFound for an unknown league" do
      stub_request(:get, league_url).to_return(status: 404, headers: json, body: '{"messages":["Not Found"]}')

      expect { espn.league(12_345, season: 2027) }.to raise_error(SportsIngest::NotFound) { |e|
        expect(e.source).to eq(:espn)
      }
    end

    it "sends the filter as the X-Fantasy-Filter header" do
      stub_request(:get, league_url)
        .with(headers: {"X-Fantasy-Filter" => '{"players":{"limit":5}}'})
        .to_return(status: 200, headers: json, body: "{}")

      expect(espn.league(12_345, season: 2027, filter: {players: {limit: 5}})).to eq({})
    end

    it "rejects IDs that aren't positive Integers" do
      expect { espn.league("12345", season: 2027) }.to raise_error(ArgumentError, /league_id/)
      expect { espn.league(12_345, season: 0) }.to raise_error(ArgumentError, /season/)
    end
  end

  describe "#get_json" do
    it "raises ParseError for a body that isn't JSON" do
      stub_request(:get, "#{base}/seasons/2027").to_return(status: 200, body: "<html>sign in</html>")

      expect { espn.season(2027) }.to raise_error(SportsIngest::ParseError, /isn't JSON/)
    end

    it "passes extra query parameters through" do
      stub_request(:get, "#{base}/seasons/2027/players?view=kona_player_info&scoringPeriodId=3")
        .to_return(status: 200, headers: json, body: "[]")

      expect(espn.get_json("seasons/2027/players", views: ["kona_player_info"], params: {scoringPeriodId: 3}))
        .to eq([])
    end
  end

  describe "#inspect" do
    it "never shows the cookies" do
      with_cookies

      expect(espn.inspect).to include("[REDACTED]")
      expect(espn.inspect).not_to match(/s2-value|SWID-VALUE/)
    end
  end

  it "fetches season metadata", vcr: {cassette_name: "espn/fhl_season_2027"} do
    live = described_class.new(game: :hockey, http: http)

    expect(live.season(2027)).to include("id" => 2027, "gameId" => 4, "currentScoringPeriod" => a_kind_of(Hash))
  end
end
