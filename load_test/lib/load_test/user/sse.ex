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
      :start_publisher_callback
    ]
  end

  defp build_headers(context, topic) do
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
    ]
  end

  def run(context, user_name, topic, expected_messages) do
    url = context.sse_url

    Logger.debug(fn ->
      "#{user_name}: Starting SSE client on url #{url}, topic #{topic}, expecting #{length(expected_messages)} messages"
    end)

    headers = build_headers(context, topic)

    parsed_url = URI.parse(url)
    opts = %{
      tls_opts: [{:customize_hostname_check, [{:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}]}],
    }
    {:ok, conn_pid} = :gun.open(String.to_atom(parsed_url.host), parsed_url.port, opts)
    {:ok, proto} = :gun.await_up(conn_pid)
    Logger.debug(fn -> "Connection established with proto #{inspect(proto)}" end)
    stream_ref = :gun.get(conn_pid, parsed_url.path, headers)

    state = %SseState{
      user_name: user_name,
      start_time: :os.system_time(:millisecond),
      all_messages: length(expected_messages),
      current_message: 0,
      url: url,
      sse_timeout: context.sse_timeout,
      start_publisher_callback: fn ->
        LoadTest.Main.start_publisher(context, user_name, topic, expected_messages)
      end
    }

    wait_for_messages(state, conn_pid, stream_ref, expected_messages)
  end

  defp wait_for_messages(state, conn_pid, stream_ref, [first_message | remaining_messages]) do
    Logger.debug(fn -> "#{header(state)} Waiting for message: #{first_message}" end)

    result = :gun.await(conn_pid, stream_ref, state.sse_timeout)

    case result do
      {:response, _, code, _} when code == 200 ->
        Logger.debug("#{header(state)} Connected, waiting: #{length(remaining_messages) + 1} messages, url #{state.url}")
        state.start_publisher_callback.()
        wait_for_messages(state, conn_pid, stream_ref, [first_message | remaining_messages])

      {:response, _, code, _} ->
        Logger.error("#{header(state)} Error: #{inspect(code)}")
        :ok = :gun.close(conn_pid)
        Stats.inc_msg_received_http_error()
        raise("#{header(state)} Error")

      {:data, _, msg} ->
        msg = String.trim(msg)
        Logger.debug(fn -> "#{header(state)} Received message: #{inspect(msg)}" end)

        if msg =~ "event: ping" do
          wait_for_messages(state, conn_pid, stream_ref, [first_message | remaining_messages])
        else
          if check_message(state, msg, first_message) == :error do
            :ok = :gun.close(conn_pid)
            raise("#{header(state)} Message check error")
          end

          state = Map.put(state, :current_message, state.current_message + 1)
          wait_for_messages(state, conn_pid, stream_ref, remaining_messages)
        end

      msg ->
        Logger.error("#{header(state)} Unexpected message #{inspect(msg)}")
        :ok = :gun.close(conn_pid)
        raise("#{header(state)} Unexpected message")

    end
    # case result do

    # receive do
    #   {:http, {_, {:error, msg}}} ->
    #     Logger.error("#{header(state)} Http error: #{inspect(msg)}")
    #     :ok = :httpc.cancel_request(request_id)
    #     Stats.inc_msg_received_http_error()
    #     raise("#{header(state)} Http error")

    #   {:http, {_, :stream, msg}} ->
    #     msg = String.trim(msg)
    #     Logger.debug(fn -> "#{header(state)} Received message: #{inspect(msg)}" end)

    #     if msg =~ "event: ping" do
    #       wait_for_messages(state, request_id, [first_message | remaining_messages])
    #     else
    #       if check_message(state, msg, first_message) == :error do
    #         :ok = :httpc.cancel_request(request_id)
    #         raise("#{header(state)} Message check error")
    #       end

    #       state = Map.put(state, :current_message, state.current_message + 1)
    #       wait_for_messages(state, request_id, remaining_messages)
    #     end

    #   {:http, {_, :stream_start, headers}} ->
    #     Logger.debug(fn ->
    #       "#{header(state)} Connected, waiting: #{length(remaining_messages) + 1} messages, url #{state.url}"
    #     end)

    #     state.start_publisher_callback.()

    #     wait_for_messages(state, request_id, [first_message | remaining_messages])

    #   msg ->
    #     Logger.error("#{header(state)} Unexpected message #{inspect(msg)}")
    #     :ok = :httpc.cancel_request(request_id)
    #     raise("#{header(state)} Unexpected message")
    # after
    #   state.sse_timeout ->
    #     Logger.error(
    #       "#{header(state)} Timeout waiting for message (timeout=#{state.sse_timeout}ms), remaining: #{length(remaining_messages) + 1} messages, url #{state.url}"
    #     )

    #     Stats.inc_msg_received_timeout()

    #     :ok = :httpc.cancel_request(request_id)
    #     raise("#{header(state)} Timeout waiting for message")
    # end
  end

  defp wait_for_messages(state, conn_pid, _, []) do
    :ok = :gun.close(conn_pid)
    Logger.info("#{header(state)} All messages received, url #{state.url}")
  end

  defp header(state) do
    now = :os.system_time(:millisecond)

    "#{state.user_name} / #{now - state.start_time} ms / #{state.current_message} < #{state.all_messages}: "
  end

  defp check_message(state, received_message, expected_message) do
    clean_received_message = String.replace(received_message, ~r"id: .*\nevent: .*\n", "")

    try do
      [_, ts, message, _, _] = String.split(clean_received_message, " ", parts: 5)
      current_ts = :os.system_time(:millisecond)
      delay = current_ts - String.to_integer(ts)
      Stats.observe_propagation(delay)

      Logger.debug(fn ->
        "#{header(state)} Propagation delay for message #{message} is #{delay}ms"
      end)

      if message == expected_message do
        Stats.inc_msg_received_ok()
        :ok
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
