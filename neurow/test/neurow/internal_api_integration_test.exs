defmodule Neurow.InternalApiIntegrationTest do
  use ExUnit.Case, async: true
  use Plug.Test
  import JwtHelper

  test "POST /v1/publish 200" do
    :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, "test_issuer1-bar")

    {:ok, body} = Jason.encode(%{message: "foo56", topic: "bar"})

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200

    {:ok, body} = Jason.encode(%{message: "foo57", topic: "bar"})

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200

    Process.sleep(10)

    assert_received {:pubsub_message, _, "foo56"}
    assert_received {:pubsub_message, _, "foo57"}

    conn = conn(:get, "/history/test_issuer1-bar")
    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200
    assert String.contains?(call.resp_body, "foo56")
    assert String.contains?(call.resp_body, "foo57")
  end
end
