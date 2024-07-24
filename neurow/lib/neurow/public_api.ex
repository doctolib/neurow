defmodule Neurow.PublicApi do
  require Logger
  import Plug.Conn
  use Plug.Router

  plug(:monitor_sse)

  plug(Neurow.JwtAuthPlug,
    jwk_provider: &Neurow.Configuration.public_api_issuer_jwks/1,
    audience: &Neurow.Configuration.public_api_audience/0,
    verbose_authentication_errors:
      &Neurow.Configuration.public_api_verbose_authentication_errors/0,
    max_lifetime: &Neurow.Configuration.public_api_jwt_max_lifetime/0,
    inc_error_callback: &Stats.inc_jwt_errors_public/0
  )

  plug(:match)
  plug(:dispatch)

  get "/v1/subscribe" do
    case conn.assigns[:jwt_payload] do
      %{"iss" => issuer, "sub" => sub} ->
        topic = "#{issuer}-#{sub}"

        timeout =
          case conn.req_headers |> List.keyfind("x-sse-timeout", 0) do
            nil -> Neurow.Configuration.sse_timeout()
            {"x-sse-timeout", timeout} -> String.to_integer(timeout)
          end

        keep_alive =
          case conn.req_headers |> List.keyfind("x-sse-keepalive", 0) do
            nil -> Neurow.Configuration.sse_keepalive()
            {"x-sse-keepalive", keepalive} -> String.to_integer(keepalive)
          end

        conn =
          conn
          |> put_resp_header("content-type", "text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("connection", "close")
          |> put_resp_header("access-control-allow-origin", "*")
          |> put_resp_header("x-sse-server", to_string(node()))
          |> put_resp_header("x-sse-timeout", to_string(timeout))
          |> put_resp_header("x-sse-keepalive", to_string(keep_alive))

        :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, topic)

        last_event_id = extract_last_event_id(conn)

        case last_event_id do
          :error ->
            conn |> resp(:bad_request, "Wrong value for last-event-id")

          _ ->
            conn = send_chunked(conn, 200)
            conn = import_history(conn, topic, last_event_id)

            Logger.debug("Client subscribed to #{topic}")

            last_message = :os.system_time(:millisecond)
            conn |> loop(timeout, keep_alive, last_message, last_message)
            Logger.debug("Client disconnected from #{topic}")
            conn
        end

      _ ->
        conn |> resp(:bad_request, "Expected JWT claims are missing")
    end
  end

  defp extract_last_event_id(conn) do
    case conn.req_headers |> List.keyfind("last-event-id", 0) do
      nil ->
        nil

      {"last-event-id", last_event_id} ->
        case Integer.parse(last_event_id) do
          {last_event_id, ""} -> last_event_id
          _ -> :error
        end
    end
  end

  defp import_history(conn, _, nil) do
    conn
  end

  defp import_history(conn, topic, last_event_id) do
    history = Neurow.ReceiverShardManager.get_history(topic)

    {conn, sent} = process_history(conn, last_event_id, 0, history)

    Logger.debug(fn ->
      "Imported history for #{topic}, last_event_id: #{last_event_id}, imported size: #{sent}"
    end)

    conn
  end

  defp process_history(conn, last_event_id, sent, [first | rest]) do
    {_, message} = first

    if message.timestamp > last_event_id do
      if sent == 0 do
        # Workaround: avoid to loose messages in tests
        Process.sleep(1)
      end

      conn = write_chunk(conn, message)
      process_history(conn, last_event_id, sent + 1, rest)
    else
      process_history(conn, last_event_id, sent, rest)
    end
  end

  defp process_history(conn, _, sent, []) do
    {conn, sent}
  end

  defp loop(conn, sse_timeout, keep_alive, last_message, last_ping) do
    receive do
      {:pubsub_message, message} ->
        conn = write_chunk(conn, message)
        Stats.inc_msg_published()
        new_last_message = :os.system_time(:millisecond)
        loop(conn, sse_timeout, keep_alive, new_last_message, new_last_message)
    after
      1000 ->
        now = :os.system_time(:millisecond)

        cond do
          # SSE Timeout
          now - last_message > sse_timeout ->
            Logger.debug("Client disconnected due to inactivity")
            :timeout

          # SSE Keep alive, send a ping
          now - last_ping > keep_alive ->
            chunk(conn, "event: ping\n\n")
            loop(conn, sse_timeout, keep_alive, last_message, now)

          # We need to stop
          StopListener.close_connections?() ->
            chunk(conn, "event: reconnect\n\n")
            :close

          # Nothing
          true ->
            loop(conn, sse_timeout, keep_alive, last_message, last_ping)
        end
    end
  end

  defp write_chunk(conn, message) do
    {:ok, conn} =
      chunk(
        conn,
        "id: #{message.timestamp}\nevent: #{message.event}\ndata: #{message.payload}\n\n"
      )

    conn
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp monitor_sse(conn, _) do
    {:ok, _pid} = SSEMonitor.start_link(conn)
    conn
  end
end
