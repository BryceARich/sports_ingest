# frozen_string_literal: true

RSpec.describe FixtureRecording do
  describe ".record_mode" do
    it "replays only when the env var is unset or blank" do
      expect(described_class.record_mode({})).to eq(:none)
      expect(described_class.record_mode({"SPORTS_INGEST_RECORD" => " "})).to eq(:none)
    end

    it "accepts the VCR record modes" do
      expect(described_class.record_mode({"SPORTS_INGEST_RECORD" => "all"})).to eq(:all)
      expect(described_class.record_mode({"SPORTS_INGEST_RECORD" => "new_episodes"})).to eq(:new_episodes)
    end

    it "rejects unknown modes" do
      expect { described_class.record_mode({"SPORTS_INGEST_RECORD" => "yes"}) }.to raise_error(ArgumentError, /one of/)
    end

    it "refuses to record in CI" do
      env = {"SPORTS_INGEST_RECORD" => "all", "CI" => "true"}
      expect { described_class.record_mode(env) }.to raise_error(ArgumentError, /CI only replays/)
    end
  end

  describe ".secrets" do
    it "maps each configured ESPN cookie, raw and URL-encoded, to its placeholder" do
      config = SportsIngest::Configuration.new(env: {})
      config.espn_s2 = "AEBs2/value+x"
      config.espn_swid = "{ABC-123}"

      expect(described_class.secrets(config)).to eq(
        "AEBs2/value+x" => "<ESPN_S2>", "AEBs2%2Fvalue%2Bx" => "<ESPN_S2>",
        "{ABC-123}" => "<ESPN_SWID>", "%7BABC-123%7D" => "<ESPN_SWID>"
      )
    end

    it "is empty without cookies" do
      expect(described_class.secrets(SportsIngest::Configuration.new(env: {}))).to eq({})
    end
  end

  describe ".scrub" do
    let(:interaction) do
      request = VCR::Request.new(:get, "https://lm-api-reads.fantasy.espn.com/apis/v3/games/fhl?swid=%7BABC-123%7D", "",
        {"Cookie" => ["espn_s2=s2secret; SWID={ABC-123}"], "User-Agent" => ["sports_ingest"]})
      response = VCR::Response.new(VCR::ResponseStatus.new(200, "OK"),
        {"Set-Cookie" => ["__cf_bm=abc"], "date" => ["Sun, 22 Nov 2026"], "Content-Type" => ["application/json"]},
        '{"owner":"{ABC-123}","token":"s2secret"}')
      VCR::HTTPInteraction.new(request, response).hook_aware
    end

    it "drops cookie headers and noisy response headers, keeping the rest" do
      described_class.scrub(interaction, {})

      expect(interaction.request.headers.keys).to eq(["User-Agent"])
      expect(interaction.response.headers.keys).to eq(["Content-Type"])
    end

    it "replaces secret values in the URI and body" do
      described_class.scrub(interaction, {"s2secret" => "<ESPN_S2>", "{ABC-123}" => "<ESPN_SWID>",
                                          "%7BABC-123%7D" => "<ESPN_SWID>"})

      expect(interaction.request.uri).to end_with("swid=<ESPN_SWID>")
      expect(interaction.response.body).to eq('{"owner":"<ESPN_SWID>","token":"<ESPN_S2>"}')
    end
  end

  describe "committed cassettes" do
    cassettes = Dir[File.join(FixtureRecording::CASSETTE_DIR, "**", "*.yml")]

    it "exist" do
      expect(cassettes).not_to be_empty
    end

    cassettes.each do |path|
      it "#{path.delete_prefix("#{FixtureRecording::CASSETTE_DIR}/")} has no cookies or secrets" do
        expect(described_class.leaks(File.read(path))).to be_empty
      end
    end
  end
end
