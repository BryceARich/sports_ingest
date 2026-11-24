# frozen_string_literal: true

# Files here are UTF-8 (cassettes, docs, gh output); don't depend on the shell's locale.
Encoding.default_external = Encoding::UTF_8

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)

task default: %i[spec standard]
