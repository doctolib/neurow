defmodule Http do
  require Logger
  import Plug.Conn
  use Plug.Router
  plug(MetricsPlugExporter)

  plug(:match)
  plug(:dispatch)

  match _ do
    send_resp(conn, 404, "")
  end
end
