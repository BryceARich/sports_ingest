# frozen_string_literal: true

require "zlib"

RSpec.describe SportsIngest::HTTP::Client do
  subject(:client) do
    described_class.new(source: :nhl, backoff: backoff, rate_limiter: limiter, sleeper: sleeps.method(:<<),
      configuration: config)
  end

  let(:url) { "https://api.example.test/v1/thing" }
  let(:sleeps) { [] }
  let(:backoff) { SportsIngest::HTTP::Backoff.new(base: 1, max: 30, jitter: 0) }
  let(:limiter) { SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}) }
  let(:config) do
    SportsIngest::Configuration.new(env: {}).tap { |c| c.user_agent = "spec-agent/1.0" }
  end

  describe "#get" do
    it "returns the response with status, lowercase headers, body and url" do
      stub_request(:get, url).to_return(status: 200, body: '{"ok":true}',
        headers: {"Content-Type" => "application/json; charset=utf-8"})

      response = client.get(url)

      expect(response).to have_attributes(status: 200, body: '{"ok":true}', url: url)
      expect(response.header("Content-Type")).to eq("application/json; charset=utf-8")
      expect(response.body.encoding).to eq(Encoding::UTF_8)
    end

    it "sends the configured user agent, asks for gzip and adds caller headers" do
      stub_request(:get, url).to_return(status: 200)

      client.get(url, headers: {"Accept" => "application/json"})

      expect(a_request(:get, url).with(headers: {
        "User-Agent" => "spec-agent/1.0", "Accept-Encoding" => "gzip", "Accept" => "application/json"
      })).to have_been_made.once
    end

    it "reveals Secret header values only on the wire" do
      stub_request(:get, url).to_return(status: 200)

      client.get(url, headers: {"Cookie" => SportsIngest::Secret.new("espn_s2=abc")})

      expect(a_request(:get, url).with(headers: {"Cookie" => "espn_s2=abc"})).to have_been_made
    end

    it "merges params into the query string" do
      stub_request(:get, "#{url}?a=1&b=two").to_return(status: 200)

      client.get("#{url}?a=1", params: {b: "two"})

      expect(a_request(:get, "#{url}?a=1&b=two")).to have_been_made
    end

    it "decodes gzip bodies" do
      gzipped = StringIO.new.tap { |io| Zlib::GzipWriter.wrap(io) { |gz| gz.write("hello") } }.string
      stub_request(:get, url).to_return(status: 200, body: gzipped,
        headers: {"Content-Encoding" => "gzip", "Content-Type" => "text/plain"})

      expect(client.get(url).body).to eq("hello")
    end

    it "raises ParseError for a broken gzip body" do
      stub_request(:get, url).to_return(status: 200, body: "not gzip", headers: {"Content-Encoding" => "gzip"})

      expect { client.get(url) }.to raise_error(SportsIngest::ParseError) { |e| expect(e.source).to eq(:nhl) }
    end

    it "leaves bodies of unknown media types binary" do
      stub_request(:get, url).to_return(status: 200, body: "\x00\x01", headers: {"Content-Type" => "application/octet-stream"})

      expect(client.get(url).body.encoding).to eq(Encoding::BINARY)
    end

    it "rejects URLs that aren't http(s)" do
      expect { client.get("ftp://example.test/x") }.to raise_error(SportsIngest::HTTPError, /not an http/)
    end
  end

  describe "retries" do
    it "retries 429 and 5xx with exponential backoff, then succeeds" do
      stub_request(:get, url).to_return({status: 503}, {status: 429}, {status: 500}, {status: 200, body: "ok"})

      expect(client.get(url).body).to eq("ok")
      expect(a_request(:get, url)).to have_been_made.times(4)
      expect(sleeps).to eq([1.0, 2.0, 4.0])
    end

    it "honours Retry-After seconds over its own backoff" do
      stub_request(:get, url).to_return({status: 429, headers: {"Retry-After" => "7"}}, {status: 200})

      client.get(url)

      expect(sleeps).to eq([7.0])
    end

    it "caps every delay at the backoff max" do
      stub_request(:get, url).to_return({status: 429, headers: {"Retry-After" => "3600"}}, {status: 200})

      client.get(url)

      expect(sleeps).to eq([30.0])
    end

    it "raises HTTPError with the status once retries run out" do
      stub_request(:get, url).to_return(status: 502)

      expect { client.get(url) }.to raise_error(SportsIngest::HTTPError) { |e|
        expect(e).to have_attributes(status: 502, url: url, source: :nhl)
      }
      expect(a_request(:get, url)).to have_been_made.times(4)
      expect(sleeps).to eq([1.0, 2.0, 4.0])
    end

    it "retries timeouts and connection errors, then raises HTTPError keeping the cause" do
      stub_request(:get, url).to_timeout.then.to_raise(Errno::ECONNRESET).then.to_raise(SocketError)
        .then.to_timeout

      expect { client.get(url) }.to raise_error(SportsIngest::HTTPError) { |e|
        expect(e.status).to be_nil
        expect(e.cause).to be_a(Net::OpenTimeout)
      }
      expect(a_request(:get, url)).to have_been_made.times(4)
    end

    it "recovers when the network comes back" do
      stub_request(:get, url).to_raise(Errno::ECONNREFUSED).then.to_return(status: 200, body: "ok")

      expect(client.get(url).body).to eq("ok")
      expect(sleeps).to eq([1.0])
    end

    it "doesn't retry when max_retries is 0" do
      stub_request(:get, url).to_return(status: 503)
      once = described_class.new(max_retries: 0, rate_limiter: limiter, sleeper: sleeps.method(:<<),
        configuration: config)

      expect { once.get(url) }.to raise_error(SportsIngest::HTTPError)
      expect(a_request(:get, url)).to have_been_made.once
      expect(sleeps).to be_empty
    end

    it "rejects a negative max_retries" do
      expect { described_class.new(max_retries: -1) }.to raise_error(SportsIngest::ConfigurationError)
    end
  end

  describe "error mapping" do
    {401 => SportsIngest::AuthError, 403 => SportsIngest::AuthError, 404 => SportsIngest::NotFound,
     400 => SportsIngest::HTTPError}.each do |status, error|
      it "raises #{error.name.split("::").last} on #{status} without retrying" do
        stub_request(:get, url).to_return(status: status)

        expect { client.get(url) }.to raise_error(error) { |e| expect(e.source).to eq(:nhl) }
        expect(a_request(:get, url)).to have_been_made.once
      end
    end
  end

  describe "redirects" do
    it "follows them" do
      stub_request(:get, url).to_return(status: 302, headers: {"Location" => "/v1/moved"})
      stub_request(:get, "https://api.example.test/v1/moved").to_return(status: 200, body: "moved")

      response = client.get(url)

      expect(response).to have_attributes(body: "moved", url: "https://api.example.test/v1/moved")
    end

    it "drops caller headers when a redirect leaves the host" do
      other = "https://cdn.example.test/file"
      stub_request(:get, url).to_return(status: 302, headers: {"Location" => other})
      stub_request(:get, other).to_return(status: 200)

      client.get(url, headers: {"Cookie" => "secret"})

      expect(a_request(:get, url).with(headers: {"Cookie" => "secret"})).to have_been_made
      expect(a_request(:get, other).with { |req| !req.headers.key?("Cookie") }).to have_been_made
    end

    it "gives up after MAX_REDIRECTS" do
      stub_request(:get, url).to_return(status: 301, headers: {"Location" => url})

      expect { client.get(url) }.to raise_error(SportsIngest::HTTPError, /too many redirects/)
      expect(a_request(:get, url)).to have_been_made.times(described_class::MAX_REDIRECTS + 1)
    end
  end

  describe "rate limiting" do
    it "waits on the limiter for the host before every attempt" do
      limiter = instance_double(SportsIngest::HTTP::RateLimiter, wait: 0.0)
      stub_request(:get, url).to_return({status: 500}, {status: 200})
      described_class.new(rate_limiter: limiter, sleeper: ->(_) {}, configuration: config).get(url)

      expect(limiter).to have_received(:wait).with("api.example.test").twice
    end

    it "spaces requests to the same host" do
      now = 0.0
      waits = []
      sleeper = lambda do |seconds|
        waits << seconds
        now += seconds
      end
      limiter = SportsIngest::HTTP::RateLimiter.new(interval: 0.5, clock: -> { now }, sleeper: sleeper)
      stub_request(:get, url).to_return(status: 200)
      paced = described_class.new(rate_limiter: limiter, sleeper: ->(_) {}, configuration: config)

      3.times { paced.get(url) }

      expect(waits).to eq([0.5, 0.5])
    end
  end

  it "reads the user agent from SportsIngest.configuration when none is given" do
    SportsIngest.configure { |c| c.user_agent = "global-agent/2" }
    stub_request(:get, url).to_return(status: 200)

    described_class.new(rate_limiter: limiter, sleeper: ->(_) {}).get(url)

    expect(a_request(:get, url).with(headers: {"User-Agent" => "global-agent/2"})).to have_been_made
  ensure
    SportsIngest.reset_configuration!
  end

  it "keeps header values out of #inspect" do
    expect(client.inspect).to eq("#<SportsIngest::HTTP::Client source=:nhl max_retries=3>")
  end
end
