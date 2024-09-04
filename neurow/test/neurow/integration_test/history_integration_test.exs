defmodule Neurow.IntegrationTest.HistoryIntegrationTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  setup do
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    Process.sleep(20)
    :ok
  end

  defp publish_message(payload, topic) do
    body =
      :jiffy.encode(%{
        message: %{
          event: "test-event",
          payload: payload
        },
        topic: topic
      })

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.Endpoint.call(conn, [])
    assert call.status == 200

    drop_one_message()
    drop_one_message()

    # Avoid to publish message in the same millisecond
    Process.sleep(2)
    result = :jiffy.decode(call.resp_body, [:return_maps])
    result["publish_timestamp"]
  end

  defp history(topic) do
    conn = conn(:get, "/history/#{topic}")
    call = Neurow.InternalApi.Endpoint.call(conn, [])
    assert call.status == 200
    :jiffy.decode(call.resp_body, [:return_maps])
  end

  defp drop_one_message() do
    receive do
      msg -> msg
    end
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

  defp all_messages(timeout \\ 100) do
    try do
      {:stream, msg} = next_message(timeout)
      msg <> all_messages(timeout)
    rescue
      RuntimeError -> ""
    end
  end

  defp send_subscribe(topic, headers) do
    url = "http://localhost:4000/v1/subscribe"

    headers =
      headers ++
        [
          {["Authorization"], "Bearer #{compute_jwt_token_in_req_header_public_api(topic)}"}
        ]

    {:ok, request_id} =
      :httpc.request(:get, {url, headers}, [], [{:sync, false}, {:stream, :self}])

    request_id
  end

  defp subscribe(topic, headers \\ [], timeout \\ 100) do
    request_id = send_subscribe(topic, headers)
    {:start, headers} = next_message(timeout)
    assert_headers(headers, {"content-type", "text/event-stream"})
    assert_headers(headers, {"cache-control", "no-cache"})
    assert_headers(headers, {"connection", "close"})
    request_id
  end

  defp assert_headers(headers, {key, value}) do
    assert {to_charlist(key), to_charlist(value)} in headers
  end

  defp assert_history(topic, expected_history) do
    actual_history = history(topic)
    assert length(expected_history) == length(actual_history)

    Enum.each(0..(length(expected_history) - 1), fn index ->
      assert Enum.at(expected_history, index) == Enum.at(actual_history, index)["payload"]
    end)

    drop_one_message()
    drop_one_message()
  end

  test "simple history" do
    full_history = history("test_issuer1-bar")
    assert full_history == []

    publish_message("foo56", "bar")

    assert_history("test_issuer1-bar", ["foo56"])
  end

  test "rotate" do
    assert_history("test_issuer1-bar", [])
    publish_message("message 1", "bar")
    assert_history("test_issuer1-bar", ["message 1"])
    publish_message("message 2", "bar")
    assert_history("test_issuer1-bar", ["message 1", "message 2"])
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    Process.sleep(20)
    assert_history("test_issuer1-bar", ["message 1", "message 2"])
    publish_message("message 3", "bar")
    assert_history("test_issuer1-bar", ["message 1", "message 2", "message 3"])
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    Process.sleep(20)
    assert_history("test_issuer1-bar", ["message 3"])
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    Process.sleep(20)
    assert_history("test_issuer1-bar", [])
  end
end
