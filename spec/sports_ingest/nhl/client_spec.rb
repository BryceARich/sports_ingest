# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Client do
  subject(:nhl) { described_class.new(http: http) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:json) { {"Content-Type" => "application/json"} }

  it "fetches web API paths" do
    stub_request(:get, "https://api-web.nhle.com/v1/standings/2026-11-22").to_return(status: 200, headers: json,
      body: '{"standings":[]}')

    expect(nhl.get_json("/standings/2026-11-22")).to eq("standings" => [])
  end

  it "answers to the rosters PR's names too" do
    stub_request(:get, "https://api-web.nhle.com/v1/roster/TOR/20262027").to_return(status: 200, headers: json,
      body: '{"forwards":[]}')

    expect(nhl.web("roster/TOR/20262027")).to eq("forwards" => [])
    expect(nhl.web_response("roster/TOR/20262027").status).to eq(200)
    expect(described_class::WEB_URL).to eq(described_class::BASE_URL)
  end

  it "fetches stats REST paths with query parameters" do
    stub_request(:get, "https://api.nhle.com/stats/rest/en/skater/summary")
      .with(query: {"limit" => "1", "cayenneExp" => "seasonId=20262027"})
      .to_return(status: 200, headers: json, body: '{"data":[],"total":0}')

    expect(nhl.stats_json("skater/summary", params: {limit: 1, cayenneExp: "seasonId=20262027"}))
      .to eq("data" => [], "total" => 0)
  end

  it "raises NotFound on 404" do
    stub_request(:get, "https://api-web.nhle.com/v1/player/1/landing").to_return(status: 404)

    expect { nhl.get_json("player/1/landing") }.to raise_error(SportsIngest::NotFound) { |e| expect(e.source).to eq(:nhl) }
  end

  it "raises ParseError on a body that isn't JSON" do
    stub_request(:get, "https://api-web.nhle.com/v1/score/now").to_return(status: 200, body: "<html>")

    expect { nhl.get_json("score/now") }.to raise_error(SportsIngest::ParseError, /isn't JSON/)
  end

  it "goes through the raw cache by default" do
    stub_request(:get, "https://api-web.nhle.com/v1/schedule/2026-11-22").to_return(status: 200, headers: json, body: "{}")
    config.raw_cache = :memory
    cached = described_class.new(configuration: config)

    2.times { cached.get_json("schedule/2026-11-22") }

    expect(a_request(:get, "https://api-web.nhle.com/v1/schedule/2026-11-22")).to have_been_made.once
  end
end
