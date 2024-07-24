defmodule Neurow.InternalApi.PublishRequest do
  alias Neurow.InternalApi.Message

  defstruct [:topics, :topic, :message, :messages]

  def from_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded_payload} -> {:ok, from_json(decoded_payload)}
      error -> error
    end
  end

  def from_json(payload) when is_map(payload) do
    %Neurow.InternalApi.PublishRequest{
      topic: payload["topic"],
      topics: payload["topics"],
      message:
        case payload["message"] do
          message when is_map(message) ->
            Neurow.InternalApi.Message.from_json(payload["message"])

          _ ->
            nil
        end,
      messages:
        case payload["messages"] do
          messages when is_list(messages) ->
            Enum.map(messages, fn message ->
              case message do
                message when is_map(message) -> Neurow.InternalApi.Message.from_json(message)
                _ -> nil
              end
            end)

          _ ->
            nil
        end
    }
  end

  def validate(request) do
    with(
      :ok <- validate_topics(request),
      :ok <- validate_messages(request)
    ) do
      :ok
    else
      error -> error
    end
  end

  def validate_topics(request) do
    case {request.topic, request.topics} do
      {nil, nil} ->
        {:error, "Attribute 'topic' or 'topics' is expected"}

      {topic, topics} when is_binary(topic) and is_list(topics) ->
        {:error, "Either attribute 'topic' or 'topics' is expected"}

      {topic, nil} ->
        if is_binary(topic) and bit_size(topic) > 0,
          do: :ok,
          else: {:error, "'topic' must be a non-empty string"}

      {nil, topics} ->
        if is_list(topics) and !Enum.empty?(topics) do
          case(Enum.all?(topics, fn topic -> is_binary(topic) and bit_size(topic) > 0 end)) do
            true -> :ok
            false -> {:error, "'topics' must be an non-empty array of non-empty strings"}
          end
        else
          {:error, "'topics' must be an non-empty array of non-empty strings"}
        end
    end
  end

  def validate_messages(request) do
    case {request.message, request.messages} do
      {nil, nil} ->
        {:error, "Attribute 'message' or 'messages' is expected"}

      {message, nil} when is_struct(message) ->
        Message.validate(message)

      {nil, messages} when is_list(messages) ->
        validation_error =
          messages
          |> Enum.map(fn message -> Message.validate(message) end)
          |> Enum.find(fn validation -> validation != :ok end)

        cond do
          validation_error != nil ->
            validation_error

          Enum.empty?(messages) ->
            {:error, "'messages' must be a non-empty list"}

          true ->
            :ok
        end

      {_message, _messages} ->
        {:error, "Attribute 'message' or 'messages' is expected"}
    end
  end

  def topics(request) do
    case {request.topic, request.topics} do
      {topic, nil} -> [topic]
      {nil, topics} -> topics
    end
  end

  def messages(request) do
    case {request.message, request.messages} do
      {message, nil} -> [message]
      {nil, messages} -> messages
    end
  end
end
