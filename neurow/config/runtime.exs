import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: String.to_atom(System.get_env("LOG_LEVEL") || "info")

# Public API configuration
config :neurow,
  public_api_port: String.to_integer(System.get_env("PUBLIC_API_PORT") || "4000"),
  public_api_jwt_max_lifetime:
    String.to_integer(System.get_env("PUBLIC_API_JWT_MAX_LIFETIME") || "120"),
  public_api_allowed_origins: [~r/^https:\/\/.*\.doctolib\.(fr|it|de)(:3000)?$/],
  public_api_preflight_max_age: String.to_integer(System.get_env("PREFLIGHT_MAX_AGE") || "86400"),
  public_api_context_path: System.get_env("PUBLIC_API_CONTEXT_PATH") || "",
  sse_timeout: String.to_integer(System.get_env("SSE_TIMEOUT") || "900000"),
  sse_keepalive: String.to_integer(System.get_env("SSE_KEEPALIVE") || "600000")

# Internal API configuration
config :neurow,
  internal_api_port: String.to_integer(System.get_env("INTERNAL_API_PORT") || "3000"),
  internal_api_jwt_max_lifetime:
    String.to_integer(System.get_env("INTERNAL_API_JWT_MAX_LIFETIME") || "1500")

config :neurow, ssl_keyfile: System.get_env("SSL_KEYFILE")
config :neurow, ssl_certfile: System.get_env("SSL_CERTFILE")

config :neurow,
  history_min_duration: String.to_integer(System.get_env("HISTORY_MIN_DURATION") || "30")

case config_env() do
  :prod ->
    interservice_json_config =
      :jiffy.decode(System.fetch_env!("JWT_CONFIG"), [:return_maps])

    verbose_authentication_errors =
      (System.get_env("VERBOSE_AUTHENTICATION_ERRORS") || "false") == "true"

    config :neurow,
      public_api_authentication: %{
        verbose_authentication_errors: verbose_authentication_errors,
        audience: interservice_json_config["service_name"],
        issuers: interservice_json_config["clients"]
      }

    config :neurow,
      internal_api_authentication: %{
        verbose_authentication_errors: verbose_authentication_errors,
        audience: interservice_json_config["service_name"],
        issuers: interservice_json_config["clients"]
      }

  env when env in [:dev, :test] ->
    config :neurow,
      public_api_authentication: %{
        verbose_authentication_errors: true,
        audience: "public_api",
        issuers: %{
          test_issuer1: "966KljJz--KyzyBnMOrFXfAkq9XMqWwPgdBV3cKTxsc",
          test_issuer2: "fu5E9VxCL8nhMG7jT4IXv3xarX8WIT7R-1pWFGm-sVw"
        }
      }

    config :neurow,
      internal_api_authentication: %{
        verbose_authentication_errors: true,
        audience: "internal_api",
        issuers: %{
          test_issuer1: "nLjJdNLlpdv3W4Xk7MyVCAZKD-hvza6FQ4yhUUFnjmg",
          test_issuer2: "3opQEJI3WK9ovGm9pHUQ6I3SkjlDYWZUeAUSazjv05g"
        }
      }

  _ ->
    raise "Unsupported environment"
end
