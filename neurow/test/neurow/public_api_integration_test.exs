defmodule Neurow.PublicApiIntegrationTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  @subscribe_url "http://localhost:4000/v1/subscribe"

  defp publish(topic, id, message) do
    :ok =
      Phoenix.PubSub.broadcast!(
        Neurow.PubSub,
        topic,
        {:pubsub_message,
         %Neurow.InternalApi.Message{event: "test-event", timestamp: id, payload: message}}
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

  test "GET /v1/subscribe 403" do
    conn =
      conn(:get, "/v1/subscribe")

    call = Neurow.PublicApi.call(conn, [])
    assert call.status == 403
  end

  test "GET /v1/subscribe 200 no message" do
    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo56")}"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {@subscribe_url, headers}, [], [{:sync, false}, {:stream, :self}])

    {:start, headers} = next_message()
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})

    :ok = :httpc.cancel_request(request_id)
  end

  test "GET /v1/subscribe 200 timeout" do
    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo56")}"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {@subscribe_url, headers}, [], [{:sync, false}, {:stream, :self}])

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
    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo57")}"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {@subscribe_url, headers}, [], [{:sync, false}, {:stream, :self}])

    {:start, headers} = next_message()
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})

    publish("test_issuer1-foo57", 42, "hello")
    Process.sleep(10)
    publish("test_issuer1-foo57", 43, "hello2")

    {:stream, msg} = next_message()
    assert msg == "id: 42\nevent: test-event\ndata: hello\n\n"
    {:stream, msg} = next_message()
    assert msg == "id: 43\nevent: test-event\ndata: hello2\n\n"
    :ok = :httpc.cancel_request(request_id)
  end

  test "GET /v1/subscribe 200 sse keepalive" do
    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo57")}"},
      {["x-sse-keepalive"], "100"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {@subscribe_url, headers}, [], [{:sync, false}, {:stream, :self}])

    {:start, headers} = next_message()
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})

    publish("test_issuer1-foo57", 42, "hello")
    Process.sleep(1100)

    {:stream, msg} = next_message()
    assert msg == "id: 42\nevent: test-event\ndata: hello\n\n"
    {:stream, msg} = next_message()
    assert msg == "event: ping\n\n"
    Process.sleep(1100)
    {:stream, msg} = next_message()
    assert msg == "event: ping\n\n"
    :ok = :httpc.cancel_request(request_id)
  end

  test "GET /v1/subscribe 200 sse timeout" do
    headers = [
      {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api("foo57")}"},
      {["x-sse-timeout"], "100"}
    ]

    {:ok, request_id} =
      :httpc.request(:get, {@subscribe_url, headers}, [], [{:sync, false}, {:stream, :self}])

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

  describe "preflight requests" do
    test "denies access if the request does not contain the Origin headers" do
      response =
        Neurow.PublicApi.call(
          conn(:options, "/v1/subscribe")
          |> put_req_header("access-control-request-headers", "authorization"),
          []
        )

      assert response.status == 400
    end

    test "denies access if the request does not contain the Access-Control-Request-Headers headers" do
      response =
        Neurow.PublicApi.call(
          conn(:options, "/v1/subscribe")
          |> put_req_header("origin", "https://www.doctolib.fr"),
          []
        )

      assert response.status == 400
    end

    test "denies access if the request Origin is not part of the list of allowed origins" do
      response =
        Neurow.PublicApi.call(
          conn(:options, "/v1/subscribe")
          |> put_req_header("origin", "https://www.unauthorized-domain.com")
          |> put_req_header("access-control-request-headers", "authorization"),
          []
        )

      assert response.status == 400
    end

    test "allow access if the Origin is part of the list of allowed origins" do
      response =
        Neurow.PublicApi.call(
          conn(:options, "/v1/subscribe")
          |> put_req_header("origin", "https://www.doctolib.fr")
          |> put_req_header("access-control-request-headers", "authorization"),
          []
        )

      assert response.status == 204

      assert {"access-control-allow-origin", "https://www.doctolib.fr"} in response.resp_headers,
             "access-control-allow-origin response header"

      assert {"access-control-allow-headers", "authorization"} in response.resp_headers,
             "access-control-allow-headers response header"

      assert {"access-control-allow-methods", "GET"} in response.resp_headers,
             "access-control-allow-methods response header"
    end
  end
end
