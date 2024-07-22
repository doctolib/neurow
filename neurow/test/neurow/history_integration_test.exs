defmodule Neurow.HistoryIntegrationTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  setup do
    GenServer.call(Neurow.TopicManager, {:purge})
    :ok
  end

  defp publish_message(message, topic) do
    {:ok, body} = Jason.encode(%{message: message, topic: topic})

    conn =
      conn(:post, "/v1/publish", body)
      |> put_jwt_token_in_req_header_internal_api()

    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200

    drop_one_message()
    drop_one_message()
    [[_, id]] = Regex.scan(~r/id=(\d+)/, call.resp_body)
    id
  end

  defp history(topic) do
    conn = conn(:get, "/history/#{topic}")
    call = Neurow.InternalApi.call(conn, [])
    assert call.status == 200
    {:ok, body} = Jason.decode(call.resp_body)
    body
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

  test "simple history" do
    full_history = history("test_issuer1-bar")
    assert full_history == []

    publish_message("foo56", "bar")

    full_history = history("test_issuer1-bar")
    assert length(full_history) == 1
    assert Enum.at(full_history, 0)["message"] == "foo56"
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
    Process.sleep(2)
    second_id = publish_message("foo57", "bar")
    Process.sleep(2)

    full_history = history("test_issuer1-bar")
    assert length(full_history) == 2
    assert Enum.at(full_history, 0)["message"] == "foo56"
    assert Enum.at(full_history, 1)["message"] == "foo57"
    drop_one_message()
    drop_one_message()

    request_id = subscribe("bar")

    assert_raise RuntimeError, ~r/^Timeout waiting for message$/, fn ->
      next_message()
    end

    :ok = :httpc.cancel_request(request_id)

    request_id = subscribe("bar", [{["Last-Event-ID"], first_id}])
    {:stream, msg} = next_message()
    assert msg == "id: #{second_id}\ndata: foo57\n\n"

    assert_raise RuntimeError, ~r/^Timeout waiting for message$/, fn ->
      next_message()
    end

    :ok = :httpc.cancel_request(request_id)

    # End of is history
    request_id = subscribe("bar", [{["Last-Event-ID"], second_id}])

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
        id = publish_message("message #{chunk}", "bar")
        Process.sleep(2)
        id
      end)

    start = 11
    request_id = subscribe("bar", [{["Last-Event-ID"], Enum.at(ids, start)}])
    output = all_messages()

    expected =
      Enum.reduce_while(12..100, "", fn chunk, acc ->
        {:cont, acc <> "id: #{Enum.at(ids, chunk)}\ndata: message #{chunk}\n\n"}
      end)

    assert output == expected
    :ok = :httpc.cancel_request(request_id)
  end
end
