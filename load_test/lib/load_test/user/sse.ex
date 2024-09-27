defmodule SseUser do
  require Logger

  alias SseUser.SseConnection

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

  def run(context, user_name, topic, expected_messages) do
    url = context.sse_url

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

    SseConnection.start(context, header(state), url, topic)

    receive do
      {:sse_connected, server, request_id} ->
        Logger.info(fn ->
          "#{header(state)} Connected, waiting for messages, url #{state.url}, remote server: #{server}"
        end)

        state.start_publisher_callback.()

        wait_for_messages(state, request_id, expected_messages)

      other_message ->
        Logger.error("#{header(state)} Unexpected message: #{inspect(other_message)}")
    end
  end

  defp wait_for_messages(state, request_id, [first_message | remaining_messages]) do
    Logger.info(fn -> "#{header(state)} Waiting for message: #{first_message}" end)

    receive do
      {:sse_event, sse_event} ->
        Logger.debug(fn -> "#{header(state)} Received message: #{inspect(sse_event)}" end)
        check_message(state, sse_event, first_message)
    after
      state.sse_timeout ->
        Logger.error(
          "#{header(state)} Timeout waiting for message (timeout=#{state.sse_timeout}ms), url #{state.url}"
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
    delay = :os.system_time(:millisecond) - String.to_integer(received_message.id)
    Stats.observe_propagation(delay)

    Logger.info(fn ->
      "#{header(state)} Propagation delay for message #{received_message.data} is #{delay}ms"
    end)

    [_ts, message, _, _] = String.split(received_message.data, " ", parts: 5)

    if message == expected_message do
      Stats.inc_msg_received_ok()
    else
      Stats.inc_msg_received_unexpected_message()

      Logger.error(
        "#{header(state)} Received unexpected message on url #{state.url}: #{inspect(received_message)} instead of #{expected_message}"
      )
    end
  end

  defmodule SseConnection do
    # Start the SSE connection in a sub-process to intercept SSE events and only forward application events to the main process
    def start(context, log_context, url, topic) do
      sse_process = self()

      {:ok, _task} =
        Task.start_link(fn ->
          Logger.info("Starting SSE client on url #{url}, topic #{topic}")
          headers = build_http_headers(context, topic)

          http_request_opts = []

          {:ok, request_id} =
            :httpc.request(:get, {url, headers}, http_request_opts, [
              {:sync, false},
              {:stream, :self}
            ])

          loop(log_context, request_id, sse_process)
        end)
    end

    defp build_http_headers(context, topic) do
      iat = :os.system_time(:second)
      exp = iat + 60 * 2 - 1

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

    defp loop(log_context, request_id, main_process) do
      receive do
        {:http, {_, {:error, msg}}} ->
          Logger.error("#{log_context} Http error: #{inspect(msg)}")
          :ok = :httpc.cancel_request(request_id)
          Stats.inc_msg_received_http_error()
          raise("#{log_context} Http error")

        {:http, {_, :stream_start, headers}} ->
          {~c"x-sse-server", server} = List.keyfind(headers, ~c"x-sse-server", 0)

          send(main_process, {:sse_connected, server, request_id})

        {:http, {_, :stream, msg}} ->
          sse_event = parse_sse_event(msg)

          case sse_event.event do
            # Events not part of the application messages, they are filtered out
            event_name when event_name in ["timeout", "ping", "reconnect"] ->
              Logger.debug("Received technical SSE event: #{event_name}")

            # Event part of the application messages, they are forwarded to the main process
            _other_event ->
              send(main_process, {:sse_event, sse_event})
          end

        other_message ->
          Logger.error("#{log_context} Unexpected message #{inspect(other_message)}")
          :ok = :httpc.cancel_request(request_id)
          raise("#{log_context} Unexpected message")
      end

      loop(log_context, request_id, main_process)
    end

    defp parse_sse_event(sse_event_chunk) do
      String.split(sse_event_chunk, "\n")
      |> Enum.reject(fn line -> String.length(String.trim(line)) == 0 end)
      |> Enum.map(fn line ->
        [key, value] = String.split(line, ~r/\: ?/, parts: 2)
        {String.to_atom(key), value}
      end)
      |> Enum.into(%{})
    end
  end
end
