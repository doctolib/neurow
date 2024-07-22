defmodule Neurow.InternalApiUnitTest do
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

  test "GET /foo 404" do
    conn =
      conn(:get, "/foo")
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 404
  end

  describe "Neurow.InternalApi.PublishRequest" do
  end
end
