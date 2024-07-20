defmodule Neurow.InternalApiTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  test "GET /ping" do
    conn = conn(:get, "/ping")
    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200
  end

  test "GET /nodes" do
    conn = conn(:get, "/nodes")
    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200
  end

  test "GET /foo 403" do
    conn = conn(:get, "/foo")
    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 403
  end

  test "GET /v1/publish 403" do
    conn = conn(:post, "/v1/publish")
    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 403
  end

  defp jwt_payload() do
    iat = :os.system_time(:second)
    exp = iat + (2 * 60 - 1)

    %{
      "iss" => "test_issuer1",
      "exp" => exp,
      "iat" => iat,
      "aud" => "internal_api"
    }
  end

  test "POST /v1/publish 200" do
    jwt_payload = jwt_payload()

    conn =
      conn(:post, "/v1/publish")
      |> put_jwt_token_in_req_header(
        jwt_payload,
        JOSE.JWK.from_oct("nLjJdNLlpdv3W4Xk7MyVCAZKD-hvza6FQ4yhUUFnjmg")
      )

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200
  end
end
