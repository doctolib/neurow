defmodule SSEMonitor do
  require Logger
  use GenServer

  def start_link(conn) do
    GenServer.start_link(__MODULE__, conn)
  end

  @impl true
  def init(conn) do
    Stats.inc_connections()
    Process.flag(:trap_exit, true)
    {:ok, nil}
  end

  @impl true
  def terminate(:normal, _) do
    Stats.dec_connections()
    Logger.debug("SSE connection end")
  end

  def terminate(reason, _) do
    Stats.dec_connections()
    Logger.debug("SSE connection terminated: #{inspect(reason)}")
  end
end
