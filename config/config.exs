import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: String.to_atom(System.get_env("LOG_LEVEL") || "info")

config :neurow, public_api_port: String.to_integer(System.get_env("PUBLIC_API_PORT") || "4000")

config :neurow,
  internal_api_port: String.to_integer(System.get_env("INTERNAL_API_PORT") || "3000")

config :neurow, sse_timeout: String.to_integer(System.get_env("SSE_TIMEOUT") || "900000")

config :neurow, ssl_keyfile: System.get_env("SSL_KEYFILE")
config :neurow, ssl_certfile: System.get_env("SSL_CERTFILE")

# Must be override in per env configuration files
config :neurow,
  public_api_authentication: %{
    verbose_authentication_errors: false,
    audience: "public_api",
    issuers: %{}
  }

# Must be override in per env configuration files
config :neurow,
  internal_api_authentication: %{
    audience: "internal_api",
    verbose_authentication_errors: false,
    issuers: %{}
  }

import_config "#{config_env()}.exs"
