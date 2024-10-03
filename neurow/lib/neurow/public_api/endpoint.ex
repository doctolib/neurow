defmodule Neurow.PublicApi.Endpoint do
  require Logger
  import Plug.Conn
  use Plug.Router

  plug(:monitor_sse)

  plug(:preflight_request)

  plug(Neurow.JwtAuthPlug,
    jwk_provider: &Neurow.Configuration.public_api_issuer_jwks/1,
    audience: &Neurow.Configuration.public_api_audience/0,
    send_forbidden: &Neurow.PublicApi.Endpoint.send_forbidden/3,
    verbose_authentication_errors:
      &Neurow.Configuration.public_api_verbose_authentication_errors/0,
    max_lifetime: &Neurow.Configuration.public_api_jwt_max_lifetime/0,
    inc_error_callback: &Stats.inc_jwt_errors_public/0
  )

  plug(:match)
  plug(:dispatch)

  match _ do
    context_path = Neurow.Configuration.public_api_context_path()

    case {conn.method, conn.request_path} do
      {"GET", ^context_path <> "/v1/subscribe"} ->
        subscribe(conn)

      _ ->
        conn |> send_resp(404, "")
    end
  end

  defp subscribe(conn) do
    case conn.assigns[:jwt_payload] do
      %{"iss" => issuer, "sub" => sub, "exp" => exp} ->
        topic = "#{issuer}-#{sub}"

        timeout_ms = Neurow.Configuration.sse_timeout()
        keep_alive_ms = Neurow.Configuration.sse_keepalive()

        conn =
          conn
          |> put_resp_header("content-type", "text/event-stream")
          |> put_resp_header("access-control-allow-origin", "*")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("connection", "close")
          |> put_resp_header("x-sse-server", to_string(node()))
          |> put_resp_header("x-sse-timeout", to_string(timeout_ms))
          |> put_resp_header("x-sse-keepalive", to_string(keep_alive_ms))

        :ok = Neurow.StopListener.subscribe()
        :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, topic)

        last_event_id = extract_last_event_id(conn)

        case last_event_id do
          :error ->
            conn
            |> send_http_error(
              :bad_request,
              :invalid_last_event_id,
              "Wrong value for last-event-id"
            )

          _ ->
            Logger.debug("Client subscribed to #{topic}")

            now_ms = :os.system_time(:millisecond)

            conn
            |> send_chunked(200)
            |> import_history(topic, last_event_id)
            |> loop(timeout_ms, keep_alive_ms, now_ms, now_ms, exp)
        end

      _ ->
        conn |> resp(:bad_request, "Expected JWT claims are missing")
    end
  end

  def send_forbidden(conn, error_code, error_message) do
    send_http_error(conn, :forbidden, error_code, error_message)
  end

  def preflight_request(conn, _opts) do
    case conn.method do
      "OPTIONS" ->
        with(
          [control_request_headers] <- conn |> get_req_header("access-control-request-headers"),
          [origin] <- conn |> get_req_header("origin")
        ) do
          if origin_allowed?(origin) do
            conn
            |> put_resp_header("access-control-allow-methods", "GET")
            |> put_resp_header("access-control-allow-headers", control_request_headers)
            |> put_resp_header("access-control-allow-origin", origin)
            |> put_resp_header(
              "access-control-max-age",
              preflight_request_max_age()
            )
            |> resp(:no_content, "")
            |> halt()
          else
            conn |> resp(:bad_request, "Origin is not allowed") |> halt()
          end
        else
          _ ->
            conn |> resp(:bad_request, "Invalid preflight request") |> halt()
        end

      _ ->
        conn
    end
  end

  defp send_http_error(conn, http_status, error_code, error_message) do
    origin =
      case conn |> get_req_header("origin") do
        [origin] -> origin
        _ -> "*"
      end

    response =
      :jiffy.encode(%{
        errors: [
          %{error_code: error_code, error_message: error_message}
        ]
      })

    now = :os.system_time(:seconds)

    {:ok, conn} =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "close")
      |> send_chunked(http_status)
      |> chunk("id:#{now}\nevent: neurow_error_#{http_status}\ndata: #{response}\n\n")

    conn
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
    history = Neurow.Broker.ReceiverShardManager.get_history(topic)

    {conn, sent} = process_history(conn, last_event_id, 0, history)

    Logger.debug(fn ->
      "Imported history for #{topic}, last_event_id: #{last_event_id}, imported size: #{sent}"
    end)

    conn
  end

  defp process_history(conn, last_event_id, sent, [first | rest]) do
    {_, message} = first

    if message.timestamp > last_event_id do
      conn = write_chunk(conn, message)
      process_history(conn, last_event_id, sent + 1, rest)
    else
      process_history(conn, last_event_id, sent, rest)
    end
  end

  defp process_history(conn, _, sent, []) do
    {conn, sent}
  end

  def loop(conn, sse_timeout_ms, keep_alive_ms, last_message_ts, last_ping_ts, jwt_exp) do
    now_ms = :os.system_time(:millisecond)

    cond do
      # SSE Timeout
      now_ms - last_message_ts > sse_timeout_ms ->
        Logger.info("Client disconnected due to inactivity")
        conn |> write_chunk("event: timeout")

      # SSE Keep alive, send a ping
      now_ms - last_ping_ts > keep_alive_ms ->
        conn
        |> write_chunk("event: ping")
        |> loop(
          sse_timeout_ms,
          keep_alive_ms,
          last_message_ts,
          now_ms,
          jwt_exp
        )

      # JWT token expired
      jwt_exp * 1000 < now_ms ->
        conn |> write_chunk("event: credentials_expired")

      # Otherwise, let's wait for a message or the next tick
      true ->
        # Compute the waiting time before the next tick
        next_ping_ms = last_ping_ts + keep_alive_ms - now_ms
        timeout_ms = last_message_ts + sse_timeout_ms - now_ms
        jwt_exp_ms = jwt_exp * 1000 - now_ms

        # The Erlang process scheduler does not guarantee the `after` block will be executed with a ms precision,
        # So a small tolerance is added, also a minimum of 100ms is set to avoid busy waiting
        next_tick_ms = max(Enum.min([next_ping_ms, timeout_ms, jwt_exp_ms]) + 20, 100)

        receive do
          {:pubsub_message, message} ->
            conn = write_chunk(conn, message)
            Stats.inc_msg_published()
            new_last_message_ts = :os.system_time(:millisecond)

            conn
            |> loop(
              sse_timeout_ms,
              keep_alive_ms,
              new_last_message_ts,
              new_last_message_ts,
              jwt_exp
            )

          :shutdown ->
            Logger.debug("Client disconnected due to node shutdown")
            conn |> write_chunk("event: reconnect")

          # Consume useless messages to avoid memory overflow
          _ ->
            conn |> loop(sse_timeout_ms, keep_alive_ms, last_message_ts, last_ping_ts, jwt_exp)
        after
          next_tick_ms ->
            conn |> loop(sse_timeout_ms, keep_alive_ms, last_message_ts, last_ping_ts, jwt_exp)
        end
    end
  end

  defp write_chunk(conn, message) when is_struct(message, Neurow.Broker.Message) do
    {:ok, conn} =
      chunk(
        conn,
        "id: #{message.timestamp}\nevent: #{message.event}\ndata: #{message.payload}\n\n"
      )

    conn
  end

  defp write_chunk(conn, message) when is_binary(message) do
    {:ok, conn} = chunk(conn, "#{message}\n\n")
    conn
  end

  defp preflight_request_max_age(),
    do: Integer.to_string(Application.fetch_env!(:neurow, :public_api_preflight_max_age))

  defp origin_allowed?(origin) do
    Enum.any?(Application.fetch_env!(:neurow, :public_api_allowed_origins), fn allowed_origin ->
      String.match?(origin, allowed_origin)
    end)
  end

  defp monitor_sse(conn, _) do
    {:ok, _pid} = SSEMonitor.start_link(conn)
    conn
  end
end
