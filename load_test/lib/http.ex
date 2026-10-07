defmodule Http do
  import Plug.Conn
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/metrics" do
    format = metrics_format(conn)

    conn
    |> put_resp_content_type(format.content_type(), nil)
    |> send_resp(200, format.format())
  end

  match _ do
    send_resp(conn, 404, "")
  end

  # Some scrapers request the protobuf format and their text parsers drop
  # summaries, which expose no quantile samples in the text format.
  defp metrics_format(conn) do
    case get_req_header(conn, "accept") do
      [accept | _] -> negotiate_metrics_format(accept)
      [] -> :prometheus_text_format
    end
  end

  defp negotiate_metrics_format(accept) do
    case :accept_header.negotiate(accept, [
           {:prometheus_text_format.content_type(), :prometheus_text_format},
           {:prometheus_protobuf_format.content_type(), :prometheus_protobuf_format}
         ]) do
      :undefined -> :prometheus_text_format
      format -> format
    end
  rescue
    _ -> :prometheus_text_format
  end
end
