# frozen_string_literal: true

RSpec.describe SportsIngest::HTTP::Backoff do
  it "doubles the delay each attempt, up to max" do
    backoff = described_class.new(base: 0.5, max: 3, jitter: 0)

    expect((0..4).map { |attempt| backoff.delay(attempt) }).to eq([0.5, 1.0, 2.0, 3.0, 3.0])
  end

  it "adds up to jitter * delay at random" do
    random = instance_double(Random, rand: 0.5)
    backoff = described_class.new(base: 2, jitter: 0.25, random: random)

    expect(backoff.delay(1)).to eq(4.5) # 4 * (1 + 0.25 * 0.5)
  end

  it "stays within [delay, delay * (1 + jitter)]" do
    backoff = described_class.new(base: 1, jitter: 0.25, random: Random.new(42))

    expect(Array.new(50) { backoff.delay(2) }).to all(be_between(4.0, 5.0))
  end

  describe "Retry-After" do
    subject(:backoff) { described_class.new(base: 1, max: 60, jitter: 0) }

    it "uses a seconds value" do
      expect(backoff.delay(3, retry_after: "12")).to eq(12.0)
    end

    it "uses an HTTP date" do
      expect(backoff.delay(0, retry_after: (Time.now + 20).httpdate)).to be_within(2).of(20)
    end

    it "treats a past date as 0" do
      expect(backoff.delay(0, retry_after: (Time.now - 60).httpdate)).to eq(0.0)
    end

    it "is capped at max" do
      expect(backoff.delay(0, retry_after: "600")).to eq(60.0)
    end

    it "ignores a value it can't read" do
      expect(backoff.delay(1, retry_after: "soon")).to eq(2.0)
    end
  end

  it "rejects negative settings" do
    expect { described_class.new(base: -1) }.to raise_error(SportsIngest::ConfigurationError)
  end
end
