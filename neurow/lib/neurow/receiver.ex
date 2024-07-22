defmodule Neurow.Receiver do
  require Logger
  use GenServer

  def start_link(topic) do
    GenServer.start_link(__MODULE__, topic)
  end

  defp create_table(table_name) do
    :ets.new(table_name, [:duplicate_bag, :protected, :named_table])
  end

  @impl true
  def init(topic) do
    Logger.info("Subscribing to topic: #{topic}")
    :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, topic)
    table_name = String.to_atom("history_#{topic}")
    create_table(table_name)
    {:ok, {topic, table_name}}
    GenServer.call(Neurow.TopicManager, {:register_topic, topic})
    {:ok, {topic, table_name}}
  end

  @impl true
  def handle_info({:pubsub_message, topic, message_id, message}, state) do
    {_, table_name} = state

    :ok =
      Phoenix.PubSub.local_broadcast(Neurow.PubSub, topic, {:pubsub_message, message_id, message})

    true = :ets.insert(table_name, {String.to_atom(topic), {message_id, message}})
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_history, topic}, _, state) do
    {_, table_name} = state
    {:reply, :ets.lookup(table_name, String.to_atom(topic)), state}
  end

  # Only for tests
  @impl true
  def handle_call({:purge}, _, state) do
    {_, table_name} = state
    :ets.delete_all_objects(table_name)
    {:reply, :ok, state}
  end
end
