defmodule Neurow.TopicManager do
  require Logger
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register_topic, topic}, from, registry) do
    new_registry = Map.put(registry, topic, from)
    {:reply, :ok, new_registry}
  end

  @impl true
  def handle_call({:lookup_receiver, topic}, _, registry) do
    Map.get(registry, topic)
    |> case do
      nil -> {:reply, :error, registry}
      {receiver, _} -> {:reply, receiver, registry}
    end
  end

  def build_topic(hash) do
    "__topic#{hash}"
  end

  def hash_topic(topic, max) do
    build_topic(:erlang.phash2(topic, max))
  end
end
