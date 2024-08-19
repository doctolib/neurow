defmodule LoadTest.Application do
  @moduledoc false

  require Logger

  use Application

  @impl true
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    {:ok, port} = Application.fetch_env(:load_test, :port)
    {:ok, publish_http_pool_size} = Application.fetch_env(:load_test, :publish_http_pool_size)
    Logger.warning("Current host: #{node()}")
    Logger.warning("Starting load test on port: #{port}")

    children = [
      {Plug.Cowboy, scheme: :http, plug: Http, options: [port: port]},
      {Task.Supervisor, name: LoadTest.TaskSupervisor},
      {LoadTest.Main, []},
      {Finch,
       name: PublishFinch,
       pools: %{
         :default => [size: publish_http_pool_size]
       }}
    ]

    MetricsPlugExporter.setup()
    Stats.setup()

    opts = [strategy: :one_for_one, name: LoadTest.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
