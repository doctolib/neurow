defmodule Neurow.PublicApi do
  require Logger
  import Plug.Conn
  use Plug.Router

  plug(:monitor_sse)

  plug(Neurow.JwtAuthPlug,
    jwk_provider: &Neurow.Configuration.public_api_issuer_jwks/1,
    audience: &Neurow.Configuration.public_api_audience/0,
    verbose_authentication_errors:
      &Neurow.Configuration.public_api_verbose_authentication_errors/0
  )

  plug(:match)
  plug(:dispatch)

  get "/v1/subscribe" do
    case conn.assigns[:jwt_payload] do
      %{"iss" => issuer, "sub" => sub} ->
        topic = "#{issuer}-#{sub}"

        timeout =
          case conn.req_headers |> List.keyfind("x-sse-timeout", 0) do
            nil -> Application.fetch_env!(:neurow, :sse_timeout)
            {"x-sse-timeout", timeout} -> String.to_integer(timeout)
          end

        conn =
          conn
          |> put_resp_header("content-type", "text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("connection", "close")
          |> put_resp_header("access-control-allow-origin", "*")
          |> put_resp_header("x-sse-server", to_string(node()))

        :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, topic)

        conn = send_chunked(conn, 200)

        Logger.debug("Client subscribed to #{topic}")

        conn |> loop(timeout)
        Logger.debug("Client disconnected from #{topic}")
        conn

      _ ->
        conn |> resp(:bad_request, "Expected JWT claims are missing")
    end
  end

  defp loop(conn, sse_timeout) do
    receive do
      {:pubsub_message, msg_id, msg} ->
        {:ok, conn} = chunk(conn, "id: #{msg_id}\ndata: #{msg}\n\n")
        Stats.inc_msg_published()
        loop(conn, sse_timeout)
    after
      sse_timeout -> :timeout
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp monitor_sse(conn, _) do
    {:ok, _pid} = SSEMonitor.start_link(conn)
    conn
  end
end
