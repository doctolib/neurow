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

config :neurow,
  public_issuers: %{
    test_issuer1: [
      "966KljJz--KyzyBnMOrFXfAkq9XMqWwPgdBV3cKTxsc",
      "fu5E9VxCL8nhMG7jT4IXv3xarX8WIT7R-1pWFGm-sVw"
    ],
    test_issuer2: "XXXX"
  },
  internal_issuers: %{
    test_issuer1: [
      "nLjJdNLlpdv3W4Xk7MyVCAZKD-hvza6FQ4yhUUFnjmg",
      "3opQEJI3WK9ovGm9pHUQ6I3SkjlDYWZUeAUSazjv05g"
    ],
    test_issuer2: "XXXX"
  }
