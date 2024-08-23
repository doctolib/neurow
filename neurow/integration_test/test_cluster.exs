defmodule Neurow.IntegrationTest.TestCluster do
  use GenServer

  require Logger

  # -- Public API --

  #
  # Just starts the TestCluster GenServer, at this step nodes in the cluster are not started yet
  #
  def start(options \\ %{}) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  #
  # Starts Neurow test nodes in the cluster, according to the TestCluster configuration
  #
  def start_nodes do
    GenServer.call(__MODULE__, :start_nodes, 20_000)
  end

  #
  # Returns a summary of the cluster state that can be injected in tests
  #
  def cluster_state do
    GenServer.call(__MODULE__, :cluster_state)
  end

  # -- GenServer callbacks, should not be used directly --

  def init(options) do
    {:ok,
     %{
       started: false,
       node_prefix: options[:node_pprefix] || "neurow_test_node_",
       node_amount: options[:node_amount] || 3,
       internal_api_port_start: options[:internal_api_port_start] || 3010,
       public_api_port_start: options[:public_api_port_start] || 4010,
       history_min_duration: options[:history_min_duration] || 30,
       # List of {node, public_api_port, internal_api_port}
       nodes: []
     }}
  end

  def handle_call(:start_nodes, _from, state) do
    case state do
      %{started: true} ->
        {:reply, :already_started, state}

      %{started: false} ->
        # If the current VM does not run as a cluster node, start it
        if !Node.alive?() do
          Node.start(:testrunner, :shortnames)
        end

        # Start all neurow nodes in parallel
        nodes =
          Enum.map(1..state.node_amount, fn index ->
            Task.async(fn -> start_node(index, state) end)
          end)
          |> Enum.map(&Task.await/1)

        {:reply, :started, Map.put(%{state | started: true}, :nodes, nodes)}
    end
  end

  def handle_call(:cluster_state, _from, state) do
    {:reply,
     %{
       started: state.started,
       cluster_size: length(state.nodes),
       public_api_ports:
         Enum.map(state.nodes, fn {_node, public_api_port, _internal_api_port} ->
           public_api_port
         end),
       internal_api_ports:
         Enum.map(state.nodes, fn {_node, _public_api_port, internal_api_port} ->
           internal_api_port
         end)
     }, state}
  end

  #
  # Start a new neurow node,
  # Inspired by https://github.com/whitfin/local-cluster/blob/main/lib/local_cluster.ex#L60
  #
  defp start_node(node_index, state) do
    node_name = "#{state.node_prefix}#{node_index}"
    public_api_port = state.public_api_port_start + node_index
    internal_api_port = state.internal_api_port_start + node_index

    Logger.warn("Starting Neurow node #{node_name} ...")

    # -- Start a new Erlang node --
    {:ok, _pid, node} =
      :peer.start_link(%{name: node_name, connection: :standard_io})

    if Node.ping(node) == :pang do
      Logger.warn("Current node status: #{Node.alive?()}, state: #{:peer.get_state(node)}")
      raise "Cannot contact the #{node}"
    end

    # -- Add the Elixir & Neurow code in the Erlang VM --
    :ok = :rpc.call(node, :code, :add_paths, [:code.get_path()])

    # -- Start and configure Mix and Logger --
    {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [:mix])
    {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [:logger])

    :ok =
      :rpc.call(node, Logger, :configure, [
        [level: Logger.level(), format: "$time $metadata[$level] $message\n"]
      ])

    :ok = :rpc.call(node, Mix, :env, [Mix.env()])

    # -- Start all other libraries applications (jose, cowboy, ...) --
    other_app_names =
      Application.loaded_applications()
      |> Enum.map(fn {app_name, _, _} -> app_name end)
      |> Enum.reject(fn app_name -> app_name == :neurow end)

    {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [other_app_names])

    # -- Start Neurow --
    # 1. Get the environement defined by "config/runtime.exs"
    {:ok, neurow_env} =
      :rpc.call(node, Config.Reader, :read!, [
        "config/runtime.exs",
        [
          env: Mix.env()
        ]
      ])
      |> Keyword.fetch(:neurow)

    # 2. Apply it to the new node
    neurow_env
    |> Enum.each(fn {key, value} ->
      :rpc.call(node, Application, :put_env, [:neurow, key, value])
    end)

    # 3. Override values required by the integration test cluster
    :ok = :rpc.call(node, Application, :put_env, [:neurow, :public_api_port, public_api_port])
    :ok = :rpc.call(node, Application, :put_env, [:neurow, :internal_api_port, internal_api_port])

    :ok =
      :rpc.call(node, Application, :put_env, [
        :neurow,
        :cluster_topologies,
        [
          gossip: [
            strategy: Cluster.Strategy.Gossip
          ]
        ]
      ])

    # 4. And finally start Neurow \o/
    {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [:neurow])

    Logger.warn("Neurow node #{node_name} started")

    {node, public_api_port, internal_api_port}
  end
end
