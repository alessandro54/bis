# Configure Oj as the default JSON parser for Rails
# Oj is ~2-3x faster than the standard JSON gem
Oj.optimize_rails()

# Make Oj the default for JSON.parse and JSON.generate
# This ensures all JSON operations use Oj, including in gems
Oj.mimic_JSON()

# Set default options for best performance
Oj.default_options = {
  mode:             :compat,      # Compatible with standard JSON gem
  symbol_keys:      false,        # Keep string keys (Rails convention)
  bigdecimal_load:  :float,       # Parse decimals as floats (faster)
  allow_blank:      true,         # Allow nil/empty input
  second_precision: 3             # Millisecond precision for Time objects
}

