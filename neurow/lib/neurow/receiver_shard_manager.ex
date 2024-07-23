defmodule Neurow.ReceiverShardManager do
  require Logger
  use GenServer

  @shards 8

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init([history_min_duration]) do
    Process.send_after(
      self(),
      {:rotate_trigger, history_min_duration},
      history_min_duration * 1_000
    )

    {:ok, nil}
  end

  @impl true
  def handle_info({:rotate_trigger, history_min_duration}, state) do
    Process.send_after(
      self(),
      {:rotate_trigger, history_min_duration},
      history_min_duration * 1_000
    )

    rotate()
    {:noreply, state}
  end

  def all_pids(fun) do
    Enum.map(0..(@shards - 1), fn shard ->
      fun.({shard, Neurow.ReceiverShard.build_name(shard)})
    end)
  end

  def rotate do
    Stats.inc_history_rotate()

    all_pids(fn {_, pid} ->
      send(pid, {:rotate})
    end)
  end

  @impl true
  def handle_call({:rotate}, _, opts) do
    rotate()
    {:reply, :ok, opts}
  end

  def build_topic(shard) do
    "__topic#{shard}"
  end

  # Read from the current process, not from GenServer process
  def get_history(topic) do
    Neurow.ReceiverShard.get_history(shard_from_topic(topic), topic)
  end

  def create_receivers() do
    all_pids(fn {shard, pid} ->
      Supervisor.child_spec({Neurow.ReceiverShard, shard}, id: pid)
    end)
  end

  def broadcast(topic, message_id, message) do
    broadcast_topic = broadcast_topic(topic)

    Phoenix.PubSub.broadcast!(
      Neurow.PubSub,
      broadcast_topic,
      {:pubsub_message, topic, message_id, message}
    )
  end

  defp broadcast_topic(topic) do
    build_topic(shard_from_topic(topic))
  end

  defp shard_from_topic(topic) do
    :erlang.phash2(topic, @shards)
  end
end
