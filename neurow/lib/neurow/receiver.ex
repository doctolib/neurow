defmodule Neurow.Receiver do
  require Logger
  use GenServer

  def start_link(topic) do
    GenServer.start_link(__MODULE__, topic)
  end

  @impl true
  def init(topic) do
    Logger.info("Subscribing to topic: #{topic}")
    :ok = Phoenix.PubSub.subscribe(Neurow.PubSub, topic)
    table = :ets.new(String.to_atom("history_#{topic}"), [:duplicate_bag, :protected])
    GenServer.call(Neurow.TopicManager, {:register_topic, topic})
    {:ok, {topic, table}}
  end

  @impl true
  def handle_info({:pubsub_message, topic, message_id, message}, state) do
    {_, table} = state

    :ok =
      Phoenix.PubSub.local_broadcast(Neurow.PubSub, topic, {:pubsub_message, message_id, message})

    true = :ets.insert(table, {String.to_atom(topic), {message_id, message}})
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_history, topic}, _, state) do
    {_, table} = state
    {:reply, :ets.lookup(table, String.to_atom(topic)), state}
  end
end
