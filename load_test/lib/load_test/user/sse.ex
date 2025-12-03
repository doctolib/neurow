defmodule SseUser do
  require Logger

  defmodule SseState do
    defstruct [
      :user_name,
      :start_time,
      :all_messages,
      :current_message,
      :url,
      :sse_timeout,
      :start_publisher_callback,
      :connect_callback,
      :conn_pid,
      :stream_ref,
      :last_event_id,
      :reconnect,
      buffer: ""
    ]
  end

  defp last_event_id_header(nil), do: []
  defp last_event_id_header(last_event_id), do: [{"Last-Event-ID", last_event_id}]

  # Parse complete SSE events from buffer
  # SSE events are delimited by double newlines (\n\n)
  # Returns {list_of_complete_events, remaining_buffer}
  defp parse_sse_events(buffer) do
    # Split on double newline to find complete events
    parts = String.split(buffer, "\n\n")

    # The last part might be incomplete, so we keep it in the buffer
    {complete_events, [remaining]} = Enum.split(parts, -1)

    # Filter out empty events (from multiple consecutive \n\n)
    complete_events = Enum.reject(complete_events, &(&1 == ""))

    {complete_events, remaining}
  end

  defp build_headers(context, state, topic) do
    iat = :os.system_time(:second)
    exp = iat + context.sse_jwt_expiration

    jwt = %{
      "iss" => context.sse_jwt_issuer,
      "exp" => exp,
      "iat" => iat,
      "aud" => context.sse_jwt_audience,
      "sub" => topic
    }

    jws = %{
      "alg" => "HS256"
    }

    signed = JOSE.JWT.sign(context.sse_jwt_secret, jws, jwt)
    {%{alg: :jose_jws_alg_hmac}, compact_signed} = JOSE.JWS.compact(signed)

    [
      {["Authorization"], "Bearer #{compact_signed}"},
      {["User-Agent"], context.sse_user_agent}
    ] ++ last_event_id_header(state.last_event_id)
  end

  def run(context, user_name, topic, expected_messages) do
    url = context.sse_url

    Logger.debug(fn ->
      "#{user_name}: Starting SSE client on url #{url}, topic #{topic}, expecting #{length(expected_messages)} messages"
    end)

    parsed_url = URI.parse(url)

    opts = %{
      tls_opts: [
        {:customize_hostname_check,
         [{:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}]}
      ],
      http_opts: %{
        closing_timeout: :infinity
      }
    }

    connect_callback = fn state ->
      headers = build_headers(context, state, topic)
      {:ok, conn_pid} = :gun.open(String.to_atom(parsed_url.host), parsed_url.port, opts)
      {:ok, proto} = :gun.await_up(conn_pid)
      Logger.debug(fn -> "Connection established with proto #{inspect(proto)}" end)
      stream_ref = :gun.get(conn_pid, parsed_url.path, headers)
      state = Map.put(state, :conn_pid, conn_pid)
      state = Map.put(state, :stream_ref, stream_ref)
      state
    end

    reconnect = if context.sse_auto_reconnect, do: 0, else: -1

    state = %SseState{
      user_name: user_name,
      start_time: :os.system_time(:millisecond),
      all_messages: length(expected_messages),
      current_message: 0,
      url: url,
      sse_timeout: context.sse_timeout,
      start_publisher_callback: fn ->
        LoadTest.Main.start_publisher(context, user_name, topic, expected_messages)
      end,
      connect_callback: connect_callback,
      last_event_id: nil,
      reconnect: reconnect
    }

    state = connect_callback.(state)

    wait_for_messages(state, expected_messages)
  end

  defp reconnect(state, messages, reason) do
    :ok = :gun.close(state.conn_pid)

    if state.reconnect == -1 do
      Logger.error(fn -> "#{header(state)} Connection closed: #{reason}" end)
      Stats.inc_msg_received_http_error()
      raise("#{header(state)} Connection closed")
    end

    Logger.error("#{header(state)} Connection closed, reconnecting: #{reason}")
    Stats.inc_reconnect()
    state = state.connect_callback.(state)
    state = Map.put(state, :reconnect, state.reconnect + 1)
    # Reset buffer on reconnect
    state = Map.put(state, :buffer, "")
    wait_for_messages(state, messages)
  end

  defp wait_for_messages(state, [first_message | remaining_messages]) do
    Logger.debug(fn -> "#{header(state)} Waiting for message: #{first_message}" end)

    result = :gun.await(state.conn_pid, state.stream_ref, state.sse_timeout)

    case result do
      {:response, _, code, _} when code == 200 ->
        Logger.debug(
          "#{header(state)} Connected, waiting: #{length(remaining_messages) + 1} messages, url #{state.url}"
        )

        state =
          if state.start_publisher_callback do
            state.start_publisher_callback.()
            Map.put(state, :start_publisher_callback, nil)
          else
            state
          end

        wait_for_messages(state, [first_message | remaining_messages])

      {:response, _, code, _} ->
        Logger.error("#{header(state)} Error: #{inspect(code)}")
        :ok = :gun.close(state.conn_pid)
        Stats.inc_msg_received_http_error()
        raise("#{header(state)} Error")

      {:data, :fin, _} ->
        reconnect(state, [first_message | remaining_messages], "{:data, :fin, _}")

      {:error, {:stream_error, {:stream_error, :internal_error, :"Stream reset by server."}}} ->
        reconnect(state, [first_message | remaining_messages], "Stream reset by server.")

      {:data, :nofin, chunk} ->
        Logger.debug(fn ->
          "#{header(state)} Received chunk (#{byte_size(chunk)} bytes): #{inspect(chunk)}"
        end)

        # Accumulate chunk in buffer
        new_buffer = state.buffer <> chunk

        # Try to parse complete SSE events from buffer
        {complete_events, remaining_buffer} = parse_sse_events(new_buffer)

        Logger.debug(fn ->
          "#{header(state)} Parsed #{length(complete_events)} complete events, buffer size: #{byte_size(remaining_buffer)}"
        end)

        # Update state with new buffer
        state = Map.put(state, :buffer, remaining_buffer)

        # Process all complete events
        process_events(state, complete_events, [first_message | remaining_messages])

      msg ->
        Logger.error("#{header(state)} Unexpected message #{inspect(msg)}")
        :ok = :gun.close(state.conn_pid)
        raise("#{header(state)} Unexpected message")
    end
  end

  defp wait_for_messages(state, []) do
    :ok = :gun.close(state.conn_pid)
    Logger.info("#{header(state)} All messages received")
  end

  # Process a list of complete SSE events
  defp process_events(state, [], remaining_messages) do
    # No complete events yet, keep waiting
    wait_for_messages(state, remaining_messages)
  end

  defp process_events(state, [event | rest_events], [expected_message | remaining_messages]) do
    event = String.trim(event)

    Logger.debug(fn -> "#{header(state)} Processing event: #{inspect(event)}" end)

    # Check if this is a ping event
    if event =~ "event: ping" do
      # Skip ping events and continue processing
      process_events(state, rest_events, [expected_message | remaining_messages])
    else
      # Process the actual message
      case check_message(state, event, expected_message) do
        :error ->
          :ok = :gun.close(state.conn_pid)
          raise("#{header(state)} Message check error")

        new_state ->
          new_state = Map.put(new_state, :current_message, new_state.current_message + 1)
          process_events(new_state, rest_events, remaining_messages)
      end
    end
  end

  defp process_events(state, _events, []) do
    # All expected messages received
    wait_for_messages(state, [])
  end

  defp header(state) do
    now = :os.system_time(:millisecond)

    "#{state.user_name} / #{now - state.start_time} ms / #{state.current_message} < #{state.all_messages} / #{state.reconnect}: "
  end

  defp check_message(state, received_message, expected_message) do
    [first, _, third | _] = String.split(received_message, "\n")
    [_, id] = String.split(first, " ")

    try do
      [_, ts, message, _, _] = String.split(third, " ", parts: 5)
      current_ts = :os.system_time(:millisecond)
      delay = current_ts - String.to_integer(ts)
      Stats.observe_propagation(delay)

      Logger.debug(fn ->
        "#{header(state)} Propagation delay for message #{message} is #{delay}ms"
      end)

      if message == expected_message do
        Stats.inc_msg_received_ok()
        state = Map.put(state, :last_event_id, id)
        state
      else
        Stats.inc_msg_received_unexpected_message()

        Logger.error(
          "#{header(state)} Received unexpected message on url #{state.url}: #{inspect(received_message)} instead of #{expected_message}"
        )

        :error
      end
    rescue
      e ->
        Logger.error("#{header(state)} #{inspect(e)}")
        Stats.inc_msg_received_error()
        :error
    end
  end
end
