defmodule SsePlugTester do
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

  def call_sse(plug_endpoint, conn, assertion_fn, options \\ []) do
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
      | adapter: {SsePlugTester.PlugAdapter, conn_state}
    }
  end
end
