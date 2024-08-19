defmodule Neurow.InternalApi.Message do
  defstruct [:event, :timestamp, :payload]

  def from_json(payload) when is_binary(payload) do
    {:ok, from_json(:jiffy.decode(payload, [:return_maps]))}
  rescue
    exception -> {:error, exception}
  end

  def from_json(payload) when is_map(payload) do
    %Neurow.InternalApi.Message{
      event: payload["event"],
      timestamp: payload["timestamp"],
      payload: payload["payload"]
    }
  end

  def validate(message) do
    cond do
      message.event == nil ->
        {:error, "'event' is expected"}

      !is_binary(message.event) or bit_size(message.event) == 0 ->
        {:error, "'event' must be a non-empty string"}

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
