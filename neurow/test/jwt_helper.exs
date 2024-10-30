defmodule JwtHelper do
  use Plug.Test

  def signed_jwt_token(jwt, jwk) do
    jws = %{
      "alg" => "HS256"
    }

    signed = JOSE.JWT.sign(jwk, jws, jwt)
    {%{alg: :jose_jws_alg_hmac}, compact_signed} = JOSE.JWS.compact(signed)
    compact_signed
  end

  def put_jwt_token_in_req_header(conn, jwt, jwk, header_key) do
    jwt_token = signed_jwt_token(jwt, jwk)
    conn |> put_req_header(header_key, "Bearer #{jwt_token}")
  end

  def put_jwt_token_in_req_header_internal_api(conn, issuer \\ "test_issuer1") do
    conn
    |> put_req_header(
      "authorization",
      "Bearer #{compute_jwt_token_in_req_header_internal_api(issuer)}"
    )
    |> put_req_header("content-type", "application/json")
  end

  def compute_jwt_token_in_req_header_internal_api(issuer \\ "test_issuer1") do
    key = JOSE.JWK.from_oct("nLjJdNLlpdv3W4Xk7MyVCAZKD-hvza6FQ4yhUUFnjmg")
    iat = :os.system_time(:second)
    exp = iat + (2 * 60 - 1)

    jwt_payload = %{
      "iss" => issuer,
      "exp" => exp,
      "iat" => iat,
      "aud" => "internal_api"
    }

    signed_jwt_token(jwt_payload, key)
  end

  def compute_jwt_token_in_req_header_public_api(topic, options \\ []) do
    issuer = Keyword.get(options, :issuer, "test_issuer1")
    duration_s = Keyword.get(options, :duration_s, 2 * 60 - 1)

    key = JOSE.JWK.from_oct("966KljJz--KyzyBnMOrFXfAkq9XMqWwPgdBV3cKTxsc")
    iat = :os.system_time(:second)
    exp = iat + duration_s

    jwt_payload = %{
      "iss" => issuer,
      "exp" => exp,
      "iat" => iat,
      "aud" => "public_api",
      "sub" => topic
    }

    signed_jwt_token(jwt_payload, key)
  end
end
