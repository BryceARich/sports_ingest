# frozen_string_literal: true

# Temporary: proves CI fails on a broken spec (M1-02 acceptance). Reverted in the next commit.
RSpec.describe "CI canary" do
  it "fails on purpose" do
    expect(1).to eq(2)
  end
end
