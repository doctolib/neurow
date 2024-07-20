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

  test "GET /foo 404" do
    conn =
      conn(:get, "/foo")
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 404
  end

  test "GET /v1/publish 403" do
    conn = conn(:post, "/v1/publish")
    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 403
  end

  test "POST /v1/publish 400 nil message" do
    conn =
      conn(:post, "/v1/publish")
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 400
    assert call.resp_body == "message is nil"
  end

  test "POST /v1/publish 400 empty message" do
    {:ok, body} = Jason.encode(%{message: ""})

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 400
    assert call.resp_body == "message is empty"
  end

  test "POST /v1/publish 400 nil topic" do
    {:ok, body} = Jason.encode(%{message: "foo"})

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 400
    assert call.resp_body == "topic is nil"
  end

  test "POST /v1/publish 400 empty topic" do
    {:ok, body} = Jason.encode(%{message: "foo", topic: ""})

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 400
    assert call.resp_body == "topic is empty"
  end

  test "POST /v1/publish 200" do
    {:ok, body} = Jason.encode(%{message: "foo", topic: "bar"})

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200
    assert call.resp_body == "Published foo to test_issuer1-bar\n"
  end

  test "POST /v1/publish 403" do
    conn =
      conn(:post, "/v1/publish")
      |> put_jwt_token_in_req_header_internal_api("test_issuer_2")

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 403
  end
end
