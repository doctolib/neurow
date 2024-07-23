defmodule Neurow.InternalApiUnitTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  test "GET /ping is available without authentication" do
    conn = conn(:get, "/ping")
    call = Neurow.InternalApi.Endpoint.call(conn, [])
    assert call.status == 200
  end

  test "GET /nodes is available without authentication" do
    conn = conn(:get, "/nodes")
    call = Neurow.InternalApi.Endpoint.call(conn, [])
    assert call.status == 200
  end

  test "other routes requires a JWT token" do
    conn = conn(:get, "/foo")
    call = Neurow.InternalApi.Endpoint.call(conn, [])
    assert call.status == 403

    conn =
      conn(:get, "/foo")
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.Endpoint.call(conn, [])
    assert call.status == 404
  end

  describe "POST /v1/subscribe" do
    test "returns a 403 if called without a JWT token" do
      {:ok, body} =
        Jason.encode(%{
          message: %{type: "type_foo", payload: "foo56"},
          topic: "bar"
        })

      conn =
        conn(:post, "/v1/publish", body)

      call = Neurow.InternalApi.Endpoint.call(conn, [])
      assert call.status == 403
    end

    test "returns a 403 if called with an invalid JWT token" do
      {:ok, body} =
        Jason.encode(%{
          message: %{type: "type_foo", payload: "foo56", timestamp: 123_456},
          topic: "bar"
        })

      conn =
        conn(:post, "/v1/publish", body)
        |> put_req_header("authorization", "Basic dXNlcjpwYXNzd29yZA==")

      call = Neurow.InternalApi.Endpoint.call(conn, [])
      assert call.status == 403
    end

    test "returns a 400 error if the request payload is invalid" do
      {:ok, body} =
        Jason.encode(%{
          topic: "bar"
        })

      conn =
        conn(:post, "/v1/publish", body)
        |> put_jwt_token_in_req_header_internal_api()

      call = Neurow.InternalApi.Endpoint.call(conn, [])
      {:ok, json_body} = Jason.decode(call.resp_body)

      assert call.status == 400

      assert json_body == %{
               "errors" => [
                 %{
                   "error_code" => "invalid_payload",
                   "error_message" => "Attribute 'message' or 'messages' is expected"
                 }
               ]
             }
    end

    test "posts to only one topic if the 'topic' attribute is used" do
      :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, "test_issuer1-test-topic1")

      {:ok, body} =
        Jason.encode(%{
          message: %{type: "type_foo", payload: "foo56", timestamp: 123_456},
          topic: "test-topic1"
        })

      conn =
        conn(:post, "/v1/publish", body) |> put_jwt_token_in_req_header_internal_api()

      call = Neurow.InternalApi.Endpoint.call(conn, [])

      assert call.status == 200

      assert_received {:pubsub_message,
                       %Neurow.InternalApi.Message{
                         type: "type_foo",
                         payload: "foo56",
                         timestamp: 123_456
                       }}
    end

    test "posts to multiple topics if the 'topics' attribute is used" do
      :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, "test_issuer1-test-topic1")
      :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, "test_issuer1-test-topic2")

      {:ok, body} =
        Jason.encode(%{
          message: %{type: "type_foo", payload: "foo56", timestamp: 123_456},
          topics: ["test-topic1", "test-topic2"]
        })

      conn =
        conn(:post, "/v1/publish", body) |> put_jwt_token_in_req_header_internal_api()

      call = Neurow.InternalApi.Endpoint.call(conn, [])

      assert call.status == 200

      assert_received {:pubsub_message,
                       %Neurow.InternalApi.Message{
                         type: "type_foo",
                         payload: "foo56",
                         timestamp: 123_456
                       }}

      assert_received {:pubsub_message,
                       %Neurow.InternalApi.Message{
                         type: "type_foo",
                         payload: "foo56",
                         timestamp: 123_456
                       }}
    end

    test "posts multiple messages if the 'messages' attribute is used" do
      :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, "test_issuer1-test-topic1")

      {:ok, body} =
        Jason.encode(%{
          messages: [
            %{type: "type_foo", payload: "message 1", timestamp: 123_456},
            %{type: "type_bar", payload: "message 2", timestamp: 123_458}
          ],
          topic: "test-topic1"
        })

      conn =
        conn(:post, "/v1/publish", body) |> put_jwt_token_in_req_header_internal_api()

      call = Neurow.InternalApi.Endpoint.call(conn, [])

      assert_received {:pubsub_message,
                       %Neurow.InternalApi.Message{
                         type: "type_foo",
                         payload: "message 1",
                         timestamp: 123_456
                       }}

      assert_received {:pubsub_message,
                       %Neurow.InternalApi.Message{
                         type: "type_bar",
                         payload: "message 2",
                         timestamp: 123_458
                       }}

      assert call.status == 200
    end

    test "provides a timestamp if the message timestamp is not provided in the request payload" do
      :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, "test_issuer1-test-topic1")

      {:ok, body} =
        Jason.encode(%{
          messages: [
            %{type: "type_foo", payload: "message 1"},
            %{type: "type_bar", payload: "message 2"}
          ],
          topic: "test-topic1"
        })

      conn =
        conn(:post, "/v1/publish", body) |> put_jwt_token_in_req_header_internal_api()

      call = Neurow.InternalApi.Endpoint.call(conn, [])

      receive do
        {:pubsub_message, message} ->
          assert message.timestamp > 0
          assert message.type == "type_foo"
          assert message.payload == "message 1"
      end

      receive do
        {:pubsub_message, message} ->
          assert message.timestamp > 0
          assert message.type == "type_bar"
          assert message.payload == "message 2"
      end

      refute_receive({:pubsub_message, %Neurow.InternalApi.Message{}})

      assert call.status == 200
    end
  end
end
