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
  public_issuers: [
    test_issuer1: """
    -----BEGIN PUBLIC KEY-----
    MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA2jYkfKh6+HGq+1p9i3Ky
    DvFTyWNO376RnrcaDx5vodfXI4Y5ZQlWk2oTiGjZ4nBUQoL0y0LvMScH1CjCqj2m
    Utx7u+UP0WuUCdBHFWT8ILvzutzsqRlceGbSyvqp8WzGDOrN0Dww4DcSNDNv5V3G
    tayuemlJ4EcGOJEoAZG+sYhrU0pu81l4f/PYA9eLluBNMw2fLlJrQtqylEI17Fa3
    r/4cvf1gbzv5sVHiogYtmG3W3tzzNlPOhlClgtqtI7+PKXewM7lRGkjyBO/R2nq+
    qcSHWrm5UICI68tR4Xc4Pqw8kg56+3EAq4wcfPNGLNMAptdHgUdBLstYNjE8PpKI
    UC+pfJ8Y6By6osagjk8vyKCsk7Ik8Gipf0qhGAy1YXhv8AogyealW7GI3zUNaA8E
    uTAKU3BUA2eSRDHlJMIsaVZws7KzT4qEGdRFLGJ0rMmR4DkksVlv5MEkrpJ0ip8G
    TN8FILQNM0dXp0fmm3WeC0S7sO/G4n/4ZkSnHMDzvnrFHjdrBRAUSc4XvEaepm1O
    EbdHdfSJsh8M31TpStXFM4T+bR2/RPlkEuAq43rN9Lzd/qZ6wqfjbSCqhzKT/fN0
    TxiTBk2NsJ25TTyuQbEz26vs5+tuJ/KNvcpE8C9Q2PZWKrB56oOeMI1NK+TL0qT9
    xAIiArySRWYbW9PthSivYssCAwEAAQ==
    -----END PUBLIC KEY-----
    """,
    test_issuer2: "XXXX"
  ],
  internal_issuers: [
    test_issuer1: "nLjJdNLlpdv3W4Xk7MyVCAZKD-hvza6FQ4yhUUFnjmg",
    test_issuer2: "XXXX"
  ]
