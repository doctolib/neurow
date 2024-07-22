defmodule Neurow.Application do
  @moduledoc false

  require Logger

  use Application

  @impl true
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    {:ok, public_api_port} = Application.fetch_env(:neurow, :public_api_port)
    {:ok, internal_api_port} = Application.fetch_env(:neurow, :internal_api_port)
    Logger.warning("Current host #{node()}")

    Logger.warning("Starting internal API on port #{internal_api_port}")

    {:ok, ssl_keyfile} = Application.fetch_env(:neurow, :ssl_keyfile)
    {:ok, ssl_certfile} = Application.fetch_env(:neurow, :ssl_certfile)

    base_public_api_http_config = [
      port: public_api_port,
      protocol_options: [idle_timeout: :infinity],
      transport_options: [max_connections: :infinity]
    ]

    {sse_http_scheme, public_api_http_config} =
      if ssl_keyfile != nil do
        Logger.warning(
          "Starting public API on port #{public_api_port}, with keyfile: #{ssl_keyfile}, certfile: #{ssl_certfile}"
        )

        http_config =
          Keyword.merge(base_public_api_http_config,
            keyfile: ssl_keyfile,
            certfile: ssl_certfile,
            otp_app: :neurow
          )

        {:https, http_config}
      else
        Logger.warning("Starting public API on port #{public_api_port} without SSL")
        {:http, base_public_api_http_config}
      end

    shards = 8

    children = [
      Neurow.Configuration,
      {Phoenix.PubSub,
       name: Neurow.PubSub, options: [adapter: Phoenix.PubSub.PG2, pool_size: 10]},
      {Plug.Cowboy, scheme: :http, plug: Neurow.InternalApi, options: [port: internal_api_port]},
      {Plug.Cowboy,
       scheme: sse_http_scheme, plug: Neurow.PublicApi, options: public_api_http_config},
      {Plug.Cowboy.Drainer, refs: [Neurow.PublicApi.HTTP], shutdown: 20_000},
      {StopListener, []},
      {Neurow.TopicManager, [shards]}
    ]

    children =
      children ++
        Enum.map(0..(shards - 1), fn shard ->
          Supervisor.child_spec({Neurow.Receiver, Neurow.TopicManager.build_topic(shard)},
            id: String.to_atom("receiver_#{shard}")
          )
        end)

    MetricsPlugExporter.setup()
    Stats.setup()

    opts = [strategy: :one_for_one, name: Neurow.Supervisor]
    Supervisor.start_link(add_cluster_supervisor(children), opts)
  end

  defp ec2_ip_to_nodename(list, _) when is_list(list) do
    [sname, _] = String.split(to_string(node()), "@")

    list
    |> Enum.map(fn ip ->
      :"#{sname}@ip-#{String.replace(ip, ".", "-")}"
    end)
  end

  defp add_cluster_supervisor(children) do
    cond do
      System.get_env("K8S_SELECTOR") && System.get_env("K8S_NAMESPACE") ->
        Logger.info(
          "Starting libcluster with K8S selector: #{System.get_env("K8S_SELECTOR")} in namespace: #{System.get_env("K8S_NAMESPACE")}"
        )

        topologies = [
          k8s: [
            strategy: Cluster.Strategy.Kubernetes,
            config: [
              mode: :ip,
              kubernetes_ip_lookup_mode: :pods,
              kubernetes_node_basename: "neurow",
              kubernetes_selector: System.get_env("K8S_SELECTOR"),
              kubernetes_namespace: System.get_env("K8S_NAMESPACE"),
              polling_interval: 10_000
            ]
          ]
        ]

        children ++ [{Cluster.Supervisor, [topologies, [name: MyApp.ClusterSupervisor]]}]

      System.get_env("EPMD_CLUSTER_MEMBERS") ->
        Logger.info(
          "Starting libcluster with EMPD_CLUSTER_MEMBERS: #{System.get_env("EPMD_CLUSTER_MEMBERS")}"
        )

        topologies = [
          epmd: [
            strategy: Cluster.Strategy.Epmd,
            config: [
              hosts:
                Enum.map(
                  String.split(System.get_env("EPMD_CLUSTER_MEMBERS"), ","),
                  &String.to_atom/1
                )
            ]
          ]
        ]

        children ++ [{Cluster.Supervisor, [topologies, [name: MyApp.ClusterSupervisor]]}]

      System.get_env("EC2_CLUSTER_TAG") && System.get_env("EC2_CLUSTER_VALUE") ->
        Logger.info(
          "Starting libcluster with EC2_CLUSTER_TAG: #{System.get_env("EC2_CLUSTER_TAG")}"
        )

        topologies = [
          ec2: [
            strategy: ClusterEC2.Strategy.Tags,
            config: [
              ec2_tagname: System.get_env("EC2_CLUSTER_TAG"),
              ec2_tagvalue: System.get_env("EC2_CLUSTER_VALUE"),
              ip_to_nodename: &ec2_ip_to_nodename/2,
              show_debug: true
            ]
          ]
        ]

        children ++ [{Cluster.Supervisor, [topologies, [name: MyApp.ClusterSupervisor]]}]

      true ->
        children
    end
  end
end
