defmodule Neurow.Observability.MetricsPlugExporter do
  @behaviour Plug
  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case conn.path_info do
      ["metrics"] ->
        conn
        |> put_resp_content_type(:prometheus_text_format.content_type(), nil)
        |> send_resp(200, :prometheus_text_format.format())
        |> halt()

      _ ->
        conn
    end
  end
end
