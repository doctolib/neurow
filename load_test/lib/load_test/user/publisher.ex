defmodule LoadTest.User.Publisher do
  require Logger

  defmodule PublisherState do
    defstruct [
      :user_name,
      :topic,
      :publish_url,
      :publish_timeout,
      :headers,
      :delay_between_messages_min,
      :delay_between_messages_max,
      :start_time
    ]
  end

  def start(context, user_name, topic, messages) do
    Logger.debug(fn ->
      "publisher_#{user_name}: Starting injector user, #{length(messages)} messages to publish"
    end)

    start_time = :os.system_time(:millisecond)
    sleep = :rand.uniform(1000) + 500
    :timer.sleep(sleep)

    state = %PublisherState{
      user_name: user_name,
      topic: topic,
      publish_url: context.publish_url,
      publish_timeout: context.publish_timeout,
      headers: build_headers(context),
      delay_between_messages_min: context.delay_between_messages_min,
      delay_between_messages_max: context.delay_between_messages_max,
      start_time: start_time
    }

    Logger.info(fn ->
      "publisher_#{state.user_name}: Start publishing #{length(messages)} messages to #{state.publish_url}, topic #{topic}"
    end)

    run(state, messages)
  end

  defp build_headers(context) do
    iat = :os.system_time(:second)
    exp = iat + 60 * 15 - 1

    jwt = %{
      "iss" => context.publish_jwt_issuer,
      "exp" => exp,
      "iat" => iat,
      "aud" => context.publish_jwt_audience
    }

    jws = %{
      "alg" => "HS256"
    }

    signed = JOSE.JWT.sign(context.publish_jwt_secret, jws, jwt)
    {%{alg: :jose_jws_alg_hmac}, compact_signed} = JOSE.JWS.compact(signed)

    [
      {"Authorization", "Bearer #{compact_signed}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp run(state, []) do
    duration = :os.system_time(:millisecond) - state.start_time

    Logger.info(fn ->
      "publisher_#{state.user_name}: All messages published to #{state.publish_url}, duration: #{duration / 1000}"
    end)
  end

  defp run(state, [first_message | messages]) do
    sleep =
      :rand.uniform(state.delay_between_messages_max - state.delay_between_messages_min) +
        state.delay_between_messages_min

    Logger.debug(fn -> "publisher_#{state.user_name}: sleep=#{sleep}ms" end)
    :timer.sleep(sleep)

    raw_message =
      "#{:os.system_time(:millisecond)} #{first_message} #{length(messages)} #{state.publish_url}"

    Logger.debug(fn ->
      "publisher_#{state.user_name}: Publishing #{inspect(raw_message)}, remaining #{length(messages)}"
    end)

    {:ok, body} =
      Jason.encode(%{
        topic: state.topic,
        message: raw_message
      })

    result =
      Finch.build(:post, state.publish_url, state.headers, body)
      |> Finch.request(PublishFinch,
        receive_timeout: state.publish_timeout,
        pool_timeout: state.publish_timeout
      )

    case result do
      {:ok, http_result} ->
        case http_result.status do
          200 ->
            Logger.debug(fn ->
              "publisher_#{state.user_name}: Message published: #{inspect(first_message)}"
            end)

            Stats.inc_msg_published_ok()

          other ->
            Stats.inc_msg_published_error()

            raise(
              "publisher_#{state.user_name}: Error publishing message #{inspect(first_message)}, status: #{other}"
            )
        end

      msg ->
        Stats.inc_msg_published_error()
        raise("publisher_#{state.user_name}: Unknown message #{inspect(msg)}")
    end

    run(state, messages)
  end
end
