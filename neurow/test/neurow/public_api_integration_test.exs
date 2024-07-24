defmodule Neurow.PublicApiIntegrationTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  test "GET /v1/subscribe 403" do
    conn =
      conn(:get, "/v1/subscribe")

    call = Neurow.PublicApi.call(conn, [])
    assert call.status == 403
  end

  defp publish(topic, id, message) do
    :ok =
      Phoenix.PubSub.broadcast!(
        Neurow.PubSub,
        topic,
        {:pubsub_message, %Neurow.InternalApi.Message{timestamp: id, payload: message}}
      )
  end

  defp next_message(timeout \\ 100) do
    receive do
      {:http, {_, {:error, msg}}} ->
        raise("Http error: #{inspect(msg)}")

      {:http, {_, :stream, msg}} ->
        {:stream, msg}

      {:http, {_, :stream_start, headers}} ->
        {:start, headers}

      {:http, {_, :stream_end, _}} ->
        {:end}

      msg ->
        raise("Unexpected message: #{inspect(msg)}")
    after
      timeout ->
        raise("Timeout waiting for message")
    end
  end

  defp assert_headers(headers, {key, value}) do
    assert {to_charlist(key), to_charlist(value)} in headers
  end

  test "GET /v1/subscribe 200 no message" do
    url = "http://localhost:4000/v1/subscribe"

    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo56")}"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {url, headers}, [], [{:sync, false}, {:stream, :self}])

    {:start, headers} = next_message()
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})

    :ok = :httpc.cancel_request(request_id)
  end

  test "GET /v1/subscribe 200 timeout" do
    url = "http://localhost:4000/v1/subscribe"

    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo56")}"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {url, headers}, [], [{:sync, false}, {:stream, :self}])

    {:start, headers} = next_message()
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})

    assert_raise RuntimeError, ~r/^Timeout waiting for message$/, fn ->
      next_message()
    end

    :ok = :httpc.cancel_request(request_id)
  end

  test "GET /v1/subscribe 200 two messages" do
    url = "http://localhost:4000/v1/subscribe"

    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo57")}"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {url, headers}, [], [{:sync, false}, {:stream, :self}])

    {:start, headers} = next_message()
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})

    publish("test_issuer1-foo57", 42, "hello")
    Process.sleep(10)
    publish("test_issuer1-foo57", 43, "hello2")

    {:stream, msg} = next_message()
    assert msg == "id: 42\ndata: hello\n\n"
    {:stream, msg} = next_message()
    assert msg == "id: 43\ndata: hello2\n\n"
    :ok = :httpc.cancel_request(request_id)
  end

  test "GET /v1/subscribe 200 sse keepalive" do
    url = "http://localhost:4000/v1/subscribe"

    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo57")}"},
      {["x-sse-keepalive"], "100"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {url, headers}, [], [{:sync, false}, {:stream, :self}])

    {:start, headers} = next_message()
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})

    publish("test_issuer1-foo57", 42, "hello")
    Process.sleep(1100)

    {:stream, msg} = next_message()
    assert msg == "id: 42\ndata: hello\n\n"
    {:stream, msg} = next_message()
    assert msg == "event: ping\n\n"
    Process.sleep(1100)
    {:stream, msg} = next_message()
    assert msg == "event: ping\n\n"
    :ok = :httpc.cancel_request(request_id)
  end

  test "GET /v1/subscribe 200 sse timeout" do
    url = "http://localhost:4000/v1/subscribe"

    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo57")}"},
      {["x-sse-timeout"], "100"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {url, headers}, [], [{:sync, false}, {:stream, :self}])

    {:start, headers} = next_message()
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})

    Process.sleep(1100)

    {:stream, msg} = next_message()
    assert msg == ""
    {:end} = next_message()
    :ok = :httpc.cancel_request(request_id)
  end
end
