defmodule Neurow.PublicApi.SSEMonitor do
  require Logger
  use GenServer

  def start_link(issuer) do
    GenServer.start_link(__MODULE__, {issuer, :os.system_time()})
  end

  @impl true
  def init({issuer, start_time}) do
    Neurow.Stats.MessageBroker.inc_subscriptions(issuer)
    Process.flag(:trap_exit, true)
    {:ok, {issuer, start_time}}
  end

  @impl true
  def terminate(:normal, {issuer, start_time}) do
    track_subscription_end(issuer, start_time)
    Logger.debug("SSE connection end")
  end

  def terminate(reason, {issuer, start_time}) do
    track_subscription_end(issuer, start_time)
    Logger.debug("SSE connection terminated: #{inspect(reason)}")
  end

  defp track_subscription_end(issuer, start_time) do
    duration_ms = System.convert_time_unit(:os.system_time() - start_time, :native, :millisecond)
    Neurow.Stats.MessageBroker.dec_subscriptions(issuer, duration_ms)
  end
end
