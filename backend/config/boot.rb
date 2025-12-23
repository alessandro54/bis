ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Temporarily disable bootsnap to resolve frozen array issues in Rails 8.1
# require "bootsnap/setup" # Speed up boot time by caching expensive operations.
