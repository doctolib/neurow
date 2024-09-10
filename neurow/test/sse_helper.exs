defmodule SseHelper do
  @moduledoc """
  Provides Helper function to test SSE connections
  - Functions at the root of the modules can be used both in unit and integration tests
  - Functions in SseHelper.PlugSse help to test Plug endpoint in unit test,
  - Functions in SSeHelper.HttpSse help to test Neurow though actual HTTP connections in integration tests
  """

  import ExUnit.Assertions

  # Common functions to parse and assert SSE events (either for unit tests and integration tests)

  def parse_sse_event(sse_event_chunk) do
    String.split(sse_event_chunk, "\n")
    |> Enum.reject(fn line -> String.length(String.trim(line)) == 0 end)
    |> Enum.map(fn line ->
      [key, value] = String.split(line, ~r/\: ?/, parts: 2)
      {String.to_atom(key), value}
    end)
    |> Enum.into(%{})
  end

  def parse_sse_json_event(sse_event_chunk) do
    sse_event = parse_sse_event(sse_event_chunk)

    %{
      sse_event
      | data:
          :jiffy.decode(
            sse_event[:data],
            [:return_maps]
          )
    }
  end

  def assert_sse_event(sse_event, expected_event, expected_data, expected_id \\ nil) do
    parsed_event = parse_sse_event(sse_event)

    assert parsed_event.event == expected_event
    assert parsed_event.data == expected_data

    if expected_id != nil do
      assert parsed_event.id == expected_id
    end
  end

  defmodule PlugSse do
    @moduledoc """
    Helper functions to test a plug SSE endpoint
    """
    defmodule PlugAdapter do
      def send_chunked(state, status, headers) do
        send(state[:owner], {:send_chunked, status})
        Plug.Adapters.Test.Conn.send_chunked(state, status, headers)
      end

      def chunk(state, body) do
        send(state[:owner], {:chunk, body})
        Plug.Adapters.Test.Conn.chunk(state, body)
      end
    end

    @doc """
    Tests interaction with a SSE request by:
     - Calling the plug endpoint in a children task,
     - Intercepts calls to `send_chunk` and `chunk` from the application plugs to send messages to the test process
    """
    def call(plug_endpoint, conn, assertion_fn, options \\ []) do
      instrumented_conn = conn |> instrument()
      call_task = Task.async(fn -> plug_endpoint.call(instrumented_conn, options) end)
      assert_receive {:plug_conn, :sent}
      assertion_fn.()
      Task.shutdown(call_task)
    end

    defp instrument(conn) do
      conn_state = conn.adapter |> elem(1)

      %Plug.Conn{
        conn
        | adapter: {SseHelper.PlugSse.PlugAdapter, conn_state}
      }
    end

    def assert_no_more_chunk do
      assert_raise(
        ExUnit.AssertionError,
        ~r/The process mailbox is empty./,
        fn ->
          assert_receive {:chunk, _}
        end
      )
    end
  end

  defmodule HttpSse do
    @moduledoc """
     Helper functions to test SSEs through actual HTTP connections
    """
    import JwtHelper

    def publish_url(port), do: "http://localhost:#{port}/v1/publish"
    def subscribe_url(port), do: "http://localhost:#{port}/v1/subscribe"

    @doc """
    Required in test setups before using HTTPoison
    """
    def ensure_started do
      Application.ensure_all_started(:httpoison)
      HTTPoison.start()
    end

    def subscribe(port, topic, assert_fn, extra_headers \\ []) do
      headers =
        [Authorization: "Bearer #{compute_jwt_token_in_req_header_public_api(topic)}"] ++
          extra_headers

      async_response = HTTPoison.get!(subscribe_url(port), headers, stream_to: self())
      assert_fn.()
      :hackney.stop_async(async_response.id)
    end

    def assert_headers(headers, expected_headers) do
      expected_headers
      |> Enum.each(fn expected_header ->
        assert headers |> Enum.member?(expected_header),
               "Expecting header #{inspect(expected_header)}"
      end)
    end

    def publish(port, topics, messages) do
      headers = [
        Authorization: "Bearer #{compute_jwt_token_in_req_header_internal_api()}",
        "content-type": "application/json"
      ]

      payload =
        %{}
        |> Map.merge(
          cond do
            is_list(topics) -> %{topics: topics}
            is_binary(topic) -> %{topic: topic}
          end
        )
        |> Map.merge(
          case messages do
            messages when is_list(messages) ->
              %{messages: messages}

            %{event: event, payload: payload, id: id} ->
              %{message: %{event: event, payload: payload, id: id}}

            %{event: event, payload: payload} ->
              %{message: %{event: event, payload: payload}}

            _ ->
              raise "Expecting %{event: event, payload: payload} or [%{event, payload, id?}]"
          end
        )

      payload_str = :jiffy.encode(payload)

      %HTTPoison.Response{status_code: status, body: body} =
        HTTPoison.post!(publish_url(port), payload_str, headers)

      assert status == 200, "Cannot publish message(s): #{status}, #{inspect(body)}"
    end

    def assert_no_more_chunk do
      assert_raise(
        ExUnit.AssertionError,
        ~r/The process mailbox is empty./,
        fn ->
          assert_receive(%HTTPoison.AsyncChunk{chunk: _chunk})
        end
      )
    end
  end
end
