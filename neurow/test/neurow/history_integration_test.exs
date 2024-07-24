defmodule Neurow.HistoryIntegrationTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  setup do
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    Process.sleep(5)
    :ok
  end

  defp publish_message(payload, topic) do
    {:ok, body} =
      Jason.encode(%{
        message: %{
          type: "test-message",
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
    result = Jason.decode!(call.resp_body)
    result["publish_timestamp"]
  end

  defp history(topic) do
    conn = conn(:get, "/history/#{topic}")
    call = Neurow.InternalApi.Endpoint.call(conn, [])
    assert call.status == 200
    {:ok, body} = Jason.decode(call.resp_body)
    body
  end

  defp drop_one_message() do
    receive do
      msg -> msg
    end
  end

  defp next_message(timeout \\ 200) do
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

  defp all_messages(timeout \\ 200) do
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

  test "no history no headers" do
    request_id = subscribe("bar")

    assert_raise RuntimeError, ~r/^Timeout waiting for message$/, fn ->
      next_message()
    end

    :ok = :httpc.cancel_request(request_id)
  end

  test "no history with headers" do
    request_id = subscribe("bar", [{["Last-Event-ID"], "3"}])

    assert_raise RuntimeError, ~r/^Timeout waiting for message$/, fn ->
      next_message()
    end

    :ok = :httpc.cancel_request(request_id)
  end

  test "last event id is a string" do
    request_id = send_subscribe("bar", [{["Last-Event-ID"], "xxx"}])

    receive do
      {:http, {_, {{_, 400, _}, _, "Wrong value for last-event-id"}}} -> :ok
      msg -> raise("Unexpected message: #{msg}")
    end

    :ok = :httpc.cancel_request(request_id)
  end

  test "last-event-id" do
    first_id = publish_message("foo56", "bar")
    second_id = publish_message("foo57", "bar")

    assert_history("test_issuer1-bar", ["foo56", "foo57"])

    request_id = subscribe("bar")

    assert_raise RuntimeError, ~r/^Timeout waiting for message$/, fn ->
      next_message()
    end

    :ok = :httpc.cancel_request(request_id)

    request_id = subscribe("bar", [{["Last-Event-ID"], to_string(first_id)}])
    {:stream, msg} = next_message()
    assert msg == "id: #{second_id}\ndata: foo57\n\n"

    assert_raise RuntimeError, ~r/^Timeout waiting for message$/, fn ->
      next_message()
    end

    :ok = :httpc.cancel_request(request_id)

    # End of is history
    request_id = subscribe("bar", [{["Last-Event-ID"], to_string(second_id)}])

    assert_raise RuntimeError, ~r/^Timeout waiting for message$/, fn ->
      next_message()
    end

    :ok = :httpc.cancel_request(request_id)

    # Unknown id
    request_id = subscribe("bar", [{["Last-Event-ID"], "12"}])
    output = all_messages()

    assert output == "id: #{first_id}\ndata: foo56\n\nid: #{second_id}\ndata: foo57\n\n"

    :ok = :httpc.cancel_request(request_id)
  end

  test "last-event-id multiple" do
    ids =
      Enum.map(0..100, fn chunk ->
        publish_message("message #{chunk}", "bar")
      end)

    start = 11
    request_id = subscribe("bar", [{["Last-Event-ID"], to_string(Enum.at(ids, start))}])
    output = all_messages()

    expected =
      Enum.reduce_while(12..100, "", fn chunk, acc ->
        {:cont, acc <> "id: #{Enum.at(ids, chunk)}\ndata: message #{chunk}\n\n"}
      end)

    assert output == expected
    :ok = :httpc.cancel_request(request_id)
  end

  test "rotate" do
    assert_history("test_issuer1-bar", [])
    publish_message("message 1", "bar")
    assert_history("test_issuer1-bar", ["message 1"])
    publish_message("message 2", "bar")
    assert_history("test_issuer1-bar", ["message 1", "message 2"])
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    Process.sleep(10)
    assert_history("test_issuer1-bar", ["message 1", "message 2"])
    publish_message("message 3", "bar")
    assert_history("test_issuer1-bar", ["message 1", "message 2", "message 3"])
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    Process.sleep(10)
    assert_history("test_issuer1-bar", ["message 3"])
    GenServer.call(Neurow.ReceiverShardManager, {:rotate})
    Process.sleep(10)
    assert_history("test_issuer1-bar", [])
  end
end
