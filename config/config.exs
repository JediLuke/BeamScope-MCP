import Config

# Port MUST be set by the consuming application (e.g. merlinex/config/config.exs or runtime.exs)
# No default — fail loudly if missing.

config :logger,
  backends: [:console]
