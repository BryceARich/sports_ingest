# frozen_string_literal: true

require "json"

# Replays a cassette recorded from the live NHL stats API, so the whole path (VCR, WebMock, the
# client's gzip handling) is exercised offline. Re-record with `rake fixtures:record`.
RSpec.describe SportsIngest::HTTP::Client, "against a recorded source" do
  subject(:client) do
    described_class.new(source: :nhl, rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end

  it "fetches one row of NHL skater totals", vcr: {cassette_name: "nhl/stats_skater_summary_limit_1"} do
    response = client.get("https://api.nhle.com/stats/rest/en/skater/summary",
      params: {limit: 1, cayenneExp: "seasonId=20252026 and gameTypeId=2"})

    payload = JSON.parse(response.body)
    expect(response.status).to eq(200)
    expect(payload).to include("data", "total")
    expect(payload["data"].first).to include("playerId", "skaterFullName", "points")
  end
end
