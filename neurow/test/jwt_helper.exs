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

  def put_jwt_token_in_req_header(conn, jwt, jwk) do
    jwt_token = signed_jwt_token(jwt, jwk)
    conn |> put_req_header("authorization", "Bearer #{jwt_token}")
  end

  def put_jwt_token_in_req_header_internal_api(conn) do
    put_jwt_token_in_req_header_internal_api(conn, "test_issuer1")
  end

  def put_jwt_token_in_req_header_internal_api(conn, issuer) do
    key = JOSE.JWK.from_oct("nLjJdNLlpdv3W4Xk7MyVCAZKD-hvza6FQ4yhUUFnjmg")
    iat = :os.system_time(:second)
    exp = iat + (2 * 60 - 1)

    jwt_payload = %{
      "iss" => issuer,
      "exp" => exp,
      "iat" => iat,
      "aud" => "internal_api"
    }

    conn
    |> put_jwt_token_in_req_header(jwt_payload, key)
    |> put_req_header("content-type", "application/json")
  end
end
