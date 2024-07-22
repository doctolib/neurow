defmodule Neurow.InternalApi.Message do
  defstruct [:type, :timestamp, :payload]

  def from_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded_payload} -> {:ok, from_json(decoded_payload)}
      error -> error
    end
  end

  def from_json(payload) when is_map(payload) do
    %Neurow.InternalApi.Message{
      type: payload["type"],
      timestamp: payload["timestamp"],
      payload: payload["payload"]
    }
  end

  def validate(message) do
    cond do
      message.type == nil ->
        {:error, "'type' is expected"}

      !is_binary(message.type) or bit_size(message.type) == 0 ->
        {:error, "'type' must be a non-empty string"}

      message.payload == nil ->
        {:error, "'payload' is expected"}

      !is_binary(message.payload) or bit_size(message.payload) == 0 ->
        {:error, "'payload' must be a non-empty string"}

      message.timestamp != nil and (!is_integer(message.timestamp) or message.timestamp < 0) ->
        {:error, "'timestamp' must be a positive integer"}

      true ->
        :ok
    end
  end
end
