defmodule Neurow.InternalApiIntegrationTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  test "POST /v1/publish 200" do
    :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, "test_issuer1-bar")

    {:ok, body} =
      Jason.encode(%{
        message: %{"type" => "type_foo", "payload" => "foo56"},
        topic: "bar"
      })

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200

    {:ok, body} =
      Jason.encode(%{"message" => %{"type" => "type_foo", "payload" => "foo57"}, topic: "bar"})

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200

    assert_received {:pubsub_message, _, %{"type" => "type_foo", "payload" => "foo56"}}
    assert_received {:pubsub_message, _, %{"type" => "type_foo", "payload" => "foo57"}}
  end
end
