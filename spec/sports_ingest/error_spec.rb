# frozen_string_literal: true

require "json"

RSpec.describe SportsIngest::Error do
  subclasses = [
    SportsIngest::HTTPError,
    SportsIngest::AuthError,
    SportsIngest::NotFound,
    SportsIngest::ParseError,
    SportsIngest::SourceChangedError
  ]

  it "is a StandardError" do
    expect(described_class.ancestors).to include(StandardError)
  end

  it "keeps the message and the failing source" do
    error = described_class.new("boom", source: :nhl)
    expect([error.message, error.source]).to eq(["boom", :nhl])
  end

  it "has no source by default" do
    expect(described_class.new("boom").source).to be_nil
  end

  subclasses.each do |klass|
    it "is the superclass of #{klass}" do
      expect(klass.superclass).to eq(described_class)
    end

    it "lets callers rescue #{klass} by rescuing SportsIngest::Error" do
      expect { raise klass.new("x", source: :espn) }.to raise_error(described_class) { |e| expect(e.source).to eq(:espn) }
    end
  end

  it "keeps the library error as cause" do
    error =
      begin
        begin
          JSON.parse("{")
        rescue JSON::ParserError
          raise SportsIngest::ParseError, "bad JSON"
        end
      rescue SportsIngest::Error => e
        e
      end
    expect(error.cause).to be_a(JSON::ParserError)
  end
end

RSpec.describe SportsIngest::HTTPError do
  it "keeps status and url" do
    error = described_class.new(status: 503, url: "https://api-web.nhle.com/v1/schedule/now", source: :nhl)
    expect([error.status, error.url, error.source]).to eq([503, "https://api-web.nhle.com/v1/schedule/now", :nhl])
  end

  it "builds a message from status and url" do
    expect(described_class.new(status: 503, url: "https://example.test/x").message)
      .to eq("HTTP request failed with status 503 for https://example.test/x")
  end

  it "builds a message without a status when no response arrived" do
    expect(described_class.new.message).to eq("HTTP request failed")
  end

  it "prefers an explicit message" do
    expect(described_class.new("timed out", url: "https://example.test/x").message).to eq("timed out")
  end
end
