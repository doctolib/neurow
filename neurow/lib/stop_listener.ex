defmodule Neurow.StopListener do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe() do
    case Registry.register(Registry.StopListener, :shutdown_subscribers, nil) do
      {:ok, _pid} -> :ok
      {:error, cause} -> {:error, cause}
    end
  end

  def shutdown() do
    GenServer.call(__MODULE__, :shutdown)
  end

  @impl true
  def init(_opts) do
    Registry.start_link(keys: :duplicate, name: Registry.StopListener)
    {:ok, %{}}
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    Logger.info("Graceful shutdown occurring ...")

    Registry.dispatch(Registry.StopListener, :shutdown_subscribers, fn entries ->
      Logger.info("Shutting down #{length(entries)} connections")

      for {pid, _value} <- entries do
        send(pid, :shutdown)
      end
    end)

    {:noreply, state}
  end
end
