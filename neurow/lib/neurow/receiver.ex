defmodule Neurow.Receiver do
  use GenServer

  def start_link(topic) do
    GenServer.start_link(__MODULE__, topic)
  end

  defp create_table(table_name) do
    :ets.new(table_name, [:duplicate_bag, :protected, :named_table])
  end

  @impl true
  def init(topic) do
    :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, topic)
    table_0 = String.to_atom("history_#{topic}_0")
    table_1 = String.to_atom("history_#{topic}_1")
    create_table(table_0)
    create_table(table_1)
    GenServer.call(Neurow.TopicManager, {:register_topic, topic})
    {:ok, {table_0, table_1}}
  end

  @impl true
  def handle_info({:pubsub_message, user_topic, message_id, message}, {table_0, table_1}) do
    :ok =
      Phoenix.PubSub.local_broadcast(Neurow.PubSub, user_topic, {:pubsub_message, message_id, message})

    true = :ets.insert(table_1, {String.to_atom(user_topic), {message_id, message}})
    {:noreply, {table_0, table_1}}
  end

  @impl true
  def handle_call({:get_history, user_topic}, _, {table_0, table_1}) do
    result = :ets.lookup(table_0, String.to_atom(user_topic)) ++
    :ets.lookup(table_1, String.to_atom(user_topic))
    {:reply, result, {table_0, table_1}}
  end

  @impl true
  def handle_call({:rotate}, _, {table_0, table_1}) do
    :ets.delete_all_objects(table_0)
    {:reply, :ok, {table_1, table_0}}
  end
end
