defmodule Neurow.TopicManager do
  require Logger
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init([shards]) do
    {:ok, {shards, %{}}}
  end

  @impl true
  def handle_call({:register_topic, topic}, from, {shards, registry}) do
    new_registry = Map.put(registry, topic, from)
    {:reply, :ok, {shards, new_registry}}
  end

  @impl true
  def handle_call({:get_history, topic}, _, {shards, registry}) do
    Map.get(registry, hash_topic(topic, shards))
    |> case do
      nil ->
        {:reply, :error, {shards, registry}}

      {receiver, _} ->
        {:reply, GenServer.call(receiver, {:get_history, topic}), {shards, registry}}
    end
  end

  @impl true
  def handle_call({:hash_topic, topic}, _, {shards, registry}) do
    {:reply, hash_topic(topic, shards), {shards, registry}}
  end

  @impl true
  def handle_call({:purge}, _, {shards, registry}) do
    result =
      Enum.map(Map.values(registry), fn {receiver, _} -> GenServer.call(receiver, {:purge}) end)

    {:reply, result, {shards, registry}}
  end

  def build_topic(hash) do
    "__topic#{hash}"
  end

  defp hash_topic(topic, shards) do
    build_topic(:erlang.phash2(topic, shards))
  end
end
