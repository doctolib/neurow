defmodule Neurow.PublicApi.Websocket do
  require Logger
  @behaviour :cowboy_websocket

  @loop_duration 5000

  def init(req, _opts) do
    Logger.debug("Starting websocket connection")

    now_ms = :os.system_time(:millisecond)

    {
      :cowboy_websocket,
      req,
      %{
        headers: req.headers,
        last_ping_ms: now_ms,
        last_message_ms: now_ms,
        sse_timeout_ms: Neurow.Configuration.sse_timeout(),
        keep_alive_ms: Neurow.Configuration.sse_keepalive(),
        jwt_exp_s: :os.system_time(:second),
        start_time: now_ms
      },
      %{
        idle_timeout: 600_000,
        max_frame_size: 1_000_000
      }
    }
  end

  defp authenticate(jwt_token, state) do
    {_, payload} = JOSE.JWT.to_map(JOSE.JWT.peek_payload(jwt_token))
    issuer = payload["iss"]
    topic = "#{issuer}-#{payload["sub"]}"
    Logger.debug("Authenticated with topic: #{topic}")
    :ok = Neurow.StopListener.subscribe()
    :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, topic)
    state = Map.put(state, :jwt_exp_s, payload["exp"])
    state = Map.put(state, :issuer, issuer)
    Neurow.Observability.MessageBrokerStats.inc_subscriptions(issuer)
    {:ok, state}
  end

  def websocket_init(state \\ %{}) do
    case state.headers["authorization"] do
      "Bearer " <> jwt_token ->
        authenticate(jwt_token, state)

      _ ->
        nil
        Logger.debug("No JWT token found in the headers")
        Process.send_after(self(), :loop, @loop_duration)
        {:ok, state}
    end
  end

  def websocket_handle({:text, frame}, state) do
    Logger.debug("Received unexpected text frame: #{inspect(frame)}")
    {:ok, state}
  end

  def websocket_info(:loop, state) do
    Process.send_after(self(), :loop, @loop_duration)
    now_ms = :os.system_time(:millisecond)

    cond do
      # Check JWT auth
      jwt_expired?(now_ms, state.jwt_exp_s) ->
        Logger.info("Client disconnected due to credentials expired")

        {[
           {:text, "event: credentials_expired\n"},
           {:close, 1000, "Credentials expired"}
         ], state}

      # SSE timeout, send a timout event and stop the connection
      sse_timed_out?(now_ms, state.last_message_ms, state.sse_timeout_ms) ->
        Logger.info("Client disconnected due to inactivity")
        {:stop, state}

      # SSE Keep alive, send a ping
      sse_needs_keepalive?(now_ms, state.last_ping_ms, state.keep_alive_ms) ->
        state = Map.put(state, :last_ping_ms, now_ms)
        {:reply, {:text, "event: ping\n"}, state}

      true ->
        {:ok, state}
    end
  end

  def websocket_info({:pubsub_message, message}, state)
      when is_struct(message, Neurow.Broker.Message) do
    Neurow.Observability.MessageBrokerStats.inc_message_sent(state.issuer)
    state = Map.put(state, :last_message_ms, :os.system_time(:millisecond))

    {:reply,
     {:text, "id: #{message.timestamp}\nevent: #{message.event}\ndata: #{message.payload}\n"},
     state}
  end

  defp sse_timed_out?(now_ms, last_message_ms, sse_timeout_ms),
    do: now_ms - last_message_ms > sse_timeout_ms

  defp sse_needs_keepalive?(now_ms, last_ping_ms, keep_alive_ms),
    do: now_ms - last_ping_ms > keep_alive_ms

  defp jwt_expired?(now_ms, jwt_exp_s),
    do: jwt_exp_s * 1000 < now_ms

  def terminate(_reason, _req, state) do
    if state.issuer do
      duration_ms =
        System.convert_time_unit(:os.system_time() - state.start_time, :native, :millisecond)

      Neurow.Observability.MessageBrokerStats.dec_subscriptions(state.issuer, duration_ms)
    end

    Logger.debug("Terminating websocket connection")
    :ok
  end
end
