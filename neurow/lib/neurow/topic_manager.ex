defmodule Neurow.TopicManager do
  require Logger
  use GenServer

  @shards 8

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    pids =
      Enum.map(0..(@shards - 1), fn shard -> Neurow.Receiver.build_name(shard) end)

    {:ok, pids}
  end

  @impl true
  def handle_call({:rotate}, _, pids) do
    Enum.each(pids, fn pid ->
      GenServer.call(pid, {:rotate})
    end)

    {:reply, :ok, pids}
  end

  def build_topic(shard) do
    "__topic#{shard}"
  end

  def broadcast_topic(topic) do
    build_topic(shard_from_topic(topic))
  end

  def shard_from_topic(topic) do
    :erlang.phash2(topic, @shards)
  end

  def get_history(topic) do
    Neurow.Receiver.get_history(shard_from_topic(topic), topic)
  end

  def shards() do
    @shards
  end
end
