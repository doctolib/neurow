defmodule Neurow.IntegrationTest.TestCluster do
  @moduledoc """
  Starts and manages a cluster of multiple Neurow nodes, started locally during integration tests
  """

  use GenServer
  require Logger

  @doc """
  Just starts the TestCluster GenServer, at this step nodes of the cluster are not started yet
  A call to this method is expected in test_helper.exs. It just starts the TestCluster GenServer so it can be used
  later in integration test cases.
  """
  def start_link(options \\ %{}) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Starts Neurow nodes in the cluster if they are not started yet, according to the TestCluster configuration
  A call to this method is expected in the setup block of integration tests
  """
  def ensure_nodes_started do
    GenServer.call(__MODULE__, :ensure_nodes_started, 20_000)
  end

  @doc """
  Returns a summary of the cluster state that can be injected in tests contexts. The result looks like:

  ```Elixir
  %{
      started: true|false,
      cluster_size: number of nodes in the cluster
      public_api_ports: ports of the public apis of each node
      internal_api_ports: ports of the internal apis of each node
    }
  ```
  """
  def cluster_state do
    GenServer.call(__MODULE__, :cluster_state)
  end

  def start_new_node() do
    GenServer.call(__MODULE__, :start_new_node)
  end

  def shutdown_node(node_name) do
    GenServer.call(__MODULE__, {:shutdown_node, node_name})
  end

  def update_sse_timeout(timeout) do
    GenServer.call(__MODULE__, {:update_timeout, timeout})
  end

  def update_sse_keepalive(keepalive) do
    GenServer.call(__MODULE__, {:update_keepalive, keepalive})
  end

  @doc """
  Flush the message history of all nodes in the cluster.
  A call to this method is expected in the setup block of integration tests
  """
  def flush_history do
    GenServer.call(__MODULE__, :flush_history)
  end

  # -- GenServer callbacks, should not be used directly --
  @impl true
  def init(options) do
    {:ok,
     %{
       started: false,
       node_prefix: options[:node_prefix] || "neurow_test_node_",
       node_amount: options[:node_amount] || 3,
       internal_api_port_start: options[:internal_api_port_start] || 3010,
       public_api_port_start: options[:public_api_port_start] || 4010,
       history_min_duration: options[:history_min_duration] || 3,
       sse_timeout: options[:internal_api_port_start] || 3000,
       # List of [{node_name, public_api_port, internal_api_port}]
       nodes: []
     }}
  end

  @impl true
  def handle_call(:ensure_nodes_started, _from, state) do
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
          |> Enum.map(fn task -> Task.await(task, 10_000) end)

        {:reply, :started, Map.put(%{state | started: true}, :nodes, nodes)}
    end
  end

  def handle_call(:flush_history, _from, state) do
    state.nodes
    |> Enum.map(fn {node, _public_api_port, _internal_api_port} ->
      Task.async(fn ->
        :ok = :rpc.call(node, Neurow.Broker.ReceiverShardManager, :flush_history, [])
      end)
    end)
    |> Enum.map(fn task -> Task.await(task, 2_000) end)

    {:reply, :flushed, state}
  end

  @impl true
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

  @impl true
  def handle_call(:start_new_node, _from, state) do
    new_node_infos = start_node(length(state.nodes) + 1, state)

    {:reply, new_node_infos,
     %{state | nodes: [new_node_infos | state.nodes], node_amount: state.node_amount + 1}}
  end

  @impl true
  def handle_call({:shutdown_node, node_name}, _from, state) do
    Logger.info("Stopping node #{node_name}")

    # Trigger a graceful shutdown of the node
    :rpc.call(node_name, :init, :stop, [])

    {:reply, :shutdown,
     %{
       state
       | nodes:
           Enum.reject(state.nodes, fn {node, _public_api_port, _internal_api_port} ->
             node == node_name
           end)
     }}
  end

  @impl true
  def handle_call({:update_timeout, timeout}, _from, state) do
    state.nodes
    |> Enum.map(fn {node, _public_api_port, _internal_api_port} ->
      :rpc.call(node, Application, :put_env, [:neurow, :sse_timeout, timeout])
    end)

    {:reply, :updated, state}
  end

  @impl true
  def handle_call({:update_keepalive, keepalive}, _from, state) do
    state.nodes
    |> Enum.map(fn {node, _public_api_port, _internal_api_port} ->
      :rpc.call(node, Application, :put_env, [:neurow, :sse_keepalive, keepalive])
    end)

    {:reply, :updated, state}
  end

  @impl true
  def terminate(_reason, state) do
    state.nodes
    |> Enum.map(fn {node_name, _public_api_port, _internal_api_port} ->
      Logger.info("Stopping node #{node_name}")
      :peer.stop(node_name)
    end)
  end

  defp start_node(node_index, state) do
    node_name = ~c"#{state.node_prefix}#{node_index}"
    public_api_port = state.public_api_port_start + node_index
    internal_api_port = state.internal_api_port_start + node_index

    Logger.info("Starting Neurow node #{node_name} ...")

    # -- Start a new Erlang node --
    {:ok, pid, node} =
      :peer.start(%{name: node_name, host: ~c"localhost", connection: :standard_io})

    if Node.ping(node) == :pang do
      Logger.warning("Current node status: #{Node.alive?()}, state: #{:peer.get_state(pid)}")
      raise "Cannot contact node #{node}"
    end

    # -- Add the Elixir & Neurow code to the Erlang VM --
    :ok = :rpc.call(node, :code, :add_paths, [:code.get_path()])

    # -- Start and configure Mix --
    {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [:mix])
    :ok = :rpc.call(node, Mix, :env, [Mix.env()])

    # -- Setup Neurow --
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
        :history_min_duration,
        state.history_min_duration
      ])

    :ok =
      :rpc.call(node, Application, :put_env, [
        :neurow,
        :sse_timeout,
        state.sse_timeout
      ])

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

    # -- Start all the applications (Neurow, and the required libraries) --
    Application.loaded_applications()
    |> Enum.map(fn {app_name, _, _} -> app_name end)
    |> Enum.each(fn app_name ->
      {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [app_name])
    end)

    Logger.info("Neurow node #{node_name} started")

    {node, public_api_port, internal_api_port}
  end
end
