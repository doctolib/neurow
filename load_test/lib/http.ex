defmodule Http do
  import Plug.Conn
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/metrics" do
    conn
    |> put_resp_content_type(:prometheus_text_format.content_type(), nil)
    |> send_resp(200, :prometheus_text_format.format())
  end

  match _ do
    send_resp(conn, 404, "")
  end
end
