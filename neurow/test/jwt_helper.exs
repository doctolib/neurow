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
end
