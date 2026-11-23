# frozen_string_literal: true

# Repo tooling behind the rake tasks in rakelib/. Not part of the gem.
module RepoTools
  # Raised when a changelog fragment, CHANGELOG.md or an ADR doesn't have the expected shape.
  class Error < StandardError; end
end
