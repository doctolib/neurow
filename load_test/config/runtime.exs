import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: String.to_atom(System.get_env("LOG_LEVEL") || "info")

config :load_test, port: String.to_integer(System.get_env("PORT") || "2999")
config :load_test, nb_user: String.to_integer(System.get_env("NB_USER") || "1")

config :load_test, sse_user_agent: System.get_env("SSE_USER_AGENT") || "neurow_load_test/1.0"
config :load_test, sse_timeout: String.to_integer(System.get_env("SSE_TIMEOUT") || "900000")
config :load_test, sse_url: System.get_env("SSE_URL") || "http://localhost:4000/v1/subscribe"
config :load_test, sse_jwt_issuer: System.get_env("SSE_JWT_ISSUER") || "test_issuer1"

config :load_test,
  sse_jwt_expiration: String.to_integer(System.get_env("SSE_JWT_EXPIRATION") || "86400")

config :load_test,
  sse_jwt_secret:
    System.get_env("SSE_JWT_SECRET") || "966KljJz--KyzyBnMOrFXfAkq9XMqWwPgdBV3cKTxsc"

config :load_test,
  sse_jwt_audience: System.get_env("SSE_JWT_AUDIENCE") || "public_api"

config :load_test,
  publish_url: System.get_env("PUBLISH_URL") || "http://localhost:3000/v1/publish"

config :load_test, publish_timeout: String.to_integer(System.get_env("PUBLISH_TIMEOUT") || "5000")

config :load_test,
  publish_http_pool_size: String.to_integer(System.get_env("PUBLISH_HTTP_POOL_SIZE") || "2000")

config :load_test, publish_jwt_issuer: System.get_env("PUBLISH_JWT_ISSUER") || "test_issuer1"

config :load_test,
  publish_jwt_secret:
    System.get_env("PUBLISH_JWT_SECRET") || "nLjJdNLlpdv3W4Xk7MyVCAZKD-hvza6FQ4yhUUFnjmg"

config :load_test,
  publish_jwt_audience: System.get_env("PUBLISH_JWT_AUDIENCE") || "internal_api"

config :load_test,
  delay_between_messages_min:
    String.to_integer(System.get_env("DELAY_BETWEEN_MESSAGES_MIN") || "500")

config :load_test,
  delay_between_messages_max:
    String.to_integer(System.get_env("DELAY_BETWEEN_MESSAGES_MAX") || "5000")

config :load_test,
  number_of_messages_min: String.to_integer(System.get_env("NUMBER_OF_MESSAGES_MIN") || "10")

config :load_test,
  number_of_messages_max: String.to_integer(System.get_env("NUMBER_OF_MESSAGES_MAX") || "50")

config :load_test,
  initial_delay_max: String.to_integer(System.get_env("INITIAL_DELAY_MAX") || "5000")
