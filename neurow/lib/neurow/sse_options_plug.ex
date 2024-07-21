defmodule Neurow.SseOptionsPlug do
  require Logger

  import Plug.Conn

  defmodule Options do
    defstruct [
      :sse_timeout
    ]

    def sse_timeout(options) do
      if is_function(options.sse_timeout),
        do: options.sse_timeout.(),
        else: options.sse_timeout
    end
  end

  def init(options), do: struct(Options, options)

  def call(conn, options) do
    conn |> assign(:sse_timeout, options |> Options.sse_timeout())
  end
end
