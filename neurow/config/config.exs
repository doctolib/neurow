# Executed at compile time

import Config

# Used by libcluster_ec2 to call the EC2 API; avoids depending on hackney
config :ex_aws, http_client: ExAws.Request.Req

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
