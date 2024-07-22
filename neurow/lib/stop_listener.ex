defmodule StopListener do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(__MODULE__, [:set, :named_table, read_concurrency: true])
    Process.flag(:trap_exit, true)
    {:ok, %{shutdown_in_progress: false}}
  end

  def close_connections?() do
    try do
      :ets.lookup(__MODULE__, :close_connections?)
      false
    rescue
      ArgumentError -> true
    end
  end

  @impl GenServer
  def terminate(_reason, _state) do
    Logger.info("Graceful Shutdown occurring")
    :ok
  end
end
