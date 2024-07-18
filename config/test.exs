#
# Configuration file used to run unit tests
#

import Config

config :neurow,
  public_api_authentication: %{
    audience: "public_api",
    issuers: %{
      test_issuer1: [
        "966KljJz--KyzyBnMOrFXfAkq9XMqWwPgdBV3cKTxsc",
        "fu5E9VxCL8nhMG7jT4IXv3xarX8WIT7R-1pWFGm-sVw"
      ],
      test_issuer2: "XXXX"
    }
  }

config :neurow,
  internal_api_authentication: %{
    audience: "internal_api",
    issuers: %{
      test_issuer1: [
        "nLjJdNLlpdv3W4Xk7MyVCAZKD-hvza6FQ4yhUUFnjmg",
        "3opQEJI3WK9ovGm9pHUQ6I3SkjlDYWZUeAUSazjv05g"
      ],
      test_issuer2: "XXXX"
    }
  }
