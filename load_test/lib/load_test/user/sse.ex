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

    [{["Authorization"], "Bearer #{compact_signed}"}]
  end

  def run(context, user_name, topic, expected_messages) do
    url = context.sse_url

    Logger.debug(fn ->
      "#{user_name}: Starting SSE client on url #{url}, topic #{topic}, expecting #{length(expected_messages)} messages"
    end)

    headers = build_headers(context, topic)
    http_request_opts = []

    {:ok, request_id} =
      :httpc.request(:get, {url, headers}, http_request_opts, [{:sync, false}, {:stream, :self}])

    state = %SseState{
      user_name: user_name,
      start_time: :os.system_time(:millisecond),
      all_messages: length(expected_messages),
      current_message: -1,
      url: url,
      sse_timeout: context.sse_timeout,
      start_publisher_callback: fn ->
        LoadTest.Main.start_publisher(context, user_name, topic, expected_messages)
      end
    }

    # Adding a padding message for the connection message
    wait_for_messages(state, request_id, ["" | expected_messages])
  end

  defp wait_for_messages(state, request_id, [first_message | remaining_messages]) do
    Logger.debug(fn -> "#{header(state)} Waiting for message: #{first_message}" end)

    receive do
      {:http, {_, {:error, msg}}} ->
        Logger.error("#{header(state)} Http error: #{inspect(msg)}")
        :ok = :httpc.cancel_request(request_id)
        Stats.inc_msg_received_http_error()
        raise("#{header(state)} Http error")

      {:http, {_, :stream, msg}} ->
        msg = String.trim(msg)
        Logger.debug(fn -> "#{header(state)} Received message: #{inspect(msg)}" end)

        if msg =~ "event: ping" do
          wait_for_messages(state, request_id, [first_message | remaining_messages])
        else
          check_message(state, msg, first_message)
        end

      {:http, {_, :stream_start, headers}} ->
        {~c"x-sse-server", server} = List.keyfind(headers, ~c"x-sse-server", 0)

        Logger.info(fn ->
          "#{header(state)} Connected, waiting: #{length(remaining_messages) + 1} messages, url #{state.url}, remote server: #{server}"
        end)

        state.start_publisher_callback.()

      msg ->
        Logger.error("#{header(state)} Unexpected message #{inspect(msg)}")
        :ok = :httpc.cancel_request(request_id)
        raise("#{header(state)} Unexpected message")
    after
      state.sse_timeout ->
        Logger.error(
          "#{header(state)} Timeout waiting for message (timeout=#{state.sse_timeout}ms), remaining: #{length(remaining_messages) + 1} messages, url #{state.url}"
        )

        Stats.inc_msg_received_timeout()

        :ok = :httpc.cancel_request(request_id)
        raise("#{header(state)} Timeout waiting for message")
    end

    state = Map.put(state, :current_message, state.current_message + 1)
    wait_for_messages(state, request_id, remaining_messages)
  end

  defp wait_for_messages(state, request_id, []) do
    :ok = :httpc.cancel_request(request_id)
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
      else
        Stats.inc_msg_received_unexpected_message()

        Logger.error(
          "#{header(state)} Received unexpected message on url #{state.url}: #{inspect(received_message)} instead of #{expected_message}"
        )
      end
    rescue
      e ->
        Logger.error("#{header(state)} #{inspect(e)}")
        Stats.inc_msg_received_error()
    end
  end
end
