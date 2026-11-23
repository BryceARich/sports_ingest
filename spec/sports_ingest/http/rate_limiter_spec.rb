# frozen_string_literal: true

RSpec.describe SportsIngest::HTTP::RateLimiter do
  subject(:limiter) { described_class.new(interval: 1.0, clock: -> { now }, sleeper: ->(s) { slept << s }) }

  let(:now) { 100.0 }
  let(:slept) { [] }

  it "lets the first request to a host through at once" do
    expect(limiter.wait("a.test")).to eq(0.0)
    expect(slept).to be_empty
  end

  it "makes back-to-back requests to one host wait one interval each" do
    3.times { limiter.wait("a.test") }

    expect(slept).to eq([1.0, 2.0]) # the clock is frozen, so each call queues behind the last
  end

  it "keeps hosts apart, ignoring case" do
    limiter.wait("a.test")
    limiter.wait("b.test")
    limiter.wait("A.TEST")

    expect(slept).to eq([1.0])
  end

  it "doesn't wait once the interval has passed" do
    clock = [100.0]
    paced = described_class.new(interval: 1.0, clock: -> { clock.first }, sleeper: ->(s) { slept << s })

    paced.wait("a.test")
    clock[0] = 101.5
    paced.wait("a.test")

    expect(slept).to be_empty
  end

  it "uses per-host intervals" do
    limiter.limit("slow.test", 3)
    limiter.wait("slow.test")
    limiter.wait("slow.test")

    expect(slept).to eq([3])
    expect(limiter.interval_for("SLOW.test")).to eq(3)
    expect(limiter.interval_for("other.test")).to eq(1.0)
  end

  it "takes per-host intervals in the constructor" do
    expect(described_class.new(intervals: {"x.test" => 0}).interval_for("x.test")).to eq(0)
  end

  it "rejects negative intervals" do
    expect { limiter.limit("a.test", -1) }.to raise_error(SportsIngest::ConfigurationError)
    expect { described_class.new(interval: "fast") }.to raise_error(SportsIngest::ConfigurationError)
  end

  it "has a shared default" do
    expect(described_class.default).to be(described_class.default).and(be_a(described_class))
    expect(described_class.default.interval_for("new.test")).to eq(described_class::DEFAULT_INTERVAL)
  end

  it "queues concurrent threads instead of letting them burst" do
    mutex = Mutex.new
    clock = 0.0
    waits = []
    shared = described_class.new(interval: 0.5, clock: -> { mutex.synchronize { clock } },
      sleeper: ->(s) { mutex.synchronize { waits << s } })

    Array.new(4) { Thread.new { shared.wait("a.test") } }.each(&:join)

    expect(waits.sort).to eq([0.5, 1.0, 1.5])
  end
end
