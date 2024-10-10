# Executed at compile time

import Config

case Mix.env() do
  :prod ->
    config :logger,
      compile_time_purge_matching: [
        [level_lower_than: :info]
      ]

  _ ->
    # Do nothing
    nil
end
