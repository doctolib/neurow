defmodule SseHelper do
  import ExUnit.Assertions

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
  # Allow to test interaction with a SSE request by:
  # - Calling the plug endpoint in a children task,
  # - Intercepts calls to `send_chunk` and `chunk` from the application plugs to send messages to the test process
  #
  def call_sse(plug_endpoint, conn, assertion_fn, options \\ []) do
    instrumented_conn = conn |> instrument()
    call_task = Task.async(fn -> plug_endpoint.call(instrumented_conn, options) end)
    assert_receive {:plug_conn, :sent}
    assertion_fn.()
    Task.shutdown(call_task)
  end

  def parse_sse_event(resp_body) do
    String.split(resp_body, "\n")
    |> Enum.reject(fn line -> String.length(String.trim(line)) == 0 end)
    |> Enum.map(fn line ->
      [key, value] = String.split(line, ~r/\: ?/, parts: 2)
      {String.to_atom(key), value}
    end)
    |> Enum.into(%{})
  end

  def parse_sse_json_event(resp_body) do
    sse_event = parse_sse_event(resp_body)

    %{
      sse_event
      | data:
          :jiffy.decode(
            sse_event[:data],
            [:return_maps]
          )
    }
  end

  defp instrument(conn) do
    conn_state = conn.adapter |> elem(1)

    %Plug.Conn{
      conn
      | adapter: {SseHelper.PlugAdapter, conn_state}
    }
  end
end
