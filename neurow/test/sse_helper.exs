defmodule SseHelper do
  import ExUnit.Assertions

  #
  # Common functions to parse and assert SSE events (either for unit tests and integration tests)
  #

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

  #
  # Helper functions to test a plug SSE endpoint
  #
  defmodule PlugSse do
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

    #
    # Tests interaction with a SSE request by:
    # - Calling the plug endpoint in a children task,
    # - Intercepts calls to `send_chunk` and `chunk` from the application plugs to send messages to the test process
    #
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
  end

  #
  # Helper functions to test SSEs through HTTP connections
  #

  defmodule HttpSse do
    import JwtHelper

    def publish_url(port), do: "http://localhost:#{port}/v1/publish"
    def subscribe_url(port), do: "http://localhost:#{port}/v1/subscribe"

    # Required in test setups before using HTTPoison
    def ensure_started do
      Application.ensure_all_started(:httpoison)
      HTTPoison.start()
    end

    def subscribe(port, topic, assert_fn) do
      headers = [Authorization: "Bearer #{compute_jwt_token_in_req_header_public_api(topic)}"]
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
          case topics do
            topics when is_list(topics) ->
              %{topics: topics}

            topic when is_binary(topic) ->
              %{topic: topic}
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

      HTTPoison.post!(publish_url(port), payload_str, headers)
    end
  end
end
