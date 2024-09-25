defmodule Neurow.Broker.ReceiverShard do
  use GenServer

  def start_link(shard) do
    GenServer.start_link(__MODULE__, shard, name: build_name(shard))
  end

  def build_name(shard) do
    String.to_atom("receiver_#{shard}")
  end

  defp create_table(table_name) do
    :ets.new(table_name, [:duplicate_bag, :protected, :named_table])
  end

  def table_name(shard, sub_shard) do
    String.to_atom("history_#{shard}_#{sub_shard}")
  end

  def flush_history(shard) do
    GenServer.call(shard, {:flush_history})
  end

  @impl true
  def init(shard) do
    :ok =
      Phoenix.PubSub.subscribe(
        Neurow.PubSub,
        Neurow.Broker.ReceiverShardManager.build_topic(shard)
      )

    table_0 = table_name(shard, 0)
    table_1 = table_name(shard, 1)
    create_table(table_0)
    create_table(table_1)
    {:ok, {table_0, table_1}}
  end

  # Read from the current process, not from GenServer process
  def get_history(shard, topic) do
    table_0 = table_name(shard, 0)
    table_1 = table_name(shard, 1)

    result = :ets.lookup(table_0, topic) ++ :ets.lookup(table_1, topic)

    Enum.sort(result, fn {_, message0}, {_, message1} ->
      message0.timestamp < message1.timestamp
    end)
  end

  @impl true
  def handle_info({:pubsub_message, user_topic, message}, {table_0, table_1}) do
    :ok =
      Phoenix.PubSub.local_broadcast(
        Neurow.PubSub,
        user_topic,
        {:pubsub_message, message}
      )

    true = :ets.insert(table_1, {user_topic, message})
    {:noreply, {table_0, table_1}}
  end

  @impl true
  def handle_info({:rotate}, {table_0, table_1}) do
    :ets.delete_all_objects(table_0)
    {:noreply, {table_1, table_0}}
  end

  @impl true
  def handle_call({:flush_history}, _from, {table_0, table_1}) do
    :ets.delete_all_objects(table_0)
    :ets.delete_all_objects(table_1)
    {:reply, :ok, {table_0, table_1}}
  end
end
