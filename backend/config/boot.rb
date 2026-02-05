ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Temporarily disable bootsnap to resolve frozen array issues in Rails 8.1.
# TODO: Re-enable bootsnap once the Rails 8.1 frozen array issue is resolved
#       (see: https://github.com/rails/rails/issues/50988 or Rails 8.2+).
# require "bootsnap/setup" # Speed up boot time by caching expensive operations.
