defmodule Neurow.TopicManager do
  require Logger
  use GenServer

  @shards 8

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  def all_pids(fun) do
    Enum.map(0..(@shards - 1), fn shard -> fun.({shard, Neurow.Receiver.build_name(shard)}) end)
  end

  @impl true
  def handle_call({:rotate}, _, opts) do
    all_pids(fn {_, pid} ->
      GenServer.call(pid, {:rotate})
    end)

    {:reply, :ok, opts}
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

  # Read from the current process, not from GenServer process
  def get_history(topic) do
    Neurow.Receiver.get_history(shard_from_topic(topic), topic)
  end

  def create_receivers() do
    all_pids(fn {shard, pid} ->
      Supervisor.child_spec({Neurow.Receiver, shard}, id: pid)
    end)
  end
end
