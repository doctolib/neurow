defmodule Neurow.Application do
  @moduledoc false

  # Resolved at compile time
  @mix_env Mix.env()

  require Logger

  use Application

  @impl true
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    public_api_port = Application.fetch_env!(:neurow, :public_api_port)
    internal_api_port = Application.fetch_env!(:neurow, :internal_api_port)
    {:ok, ssl_keyfile} = Application.fetch_env(:neurow, :ssl_keyfile)
    {:ok, ssl_certfile} = Application.fetch_env(:neurow, :ssl_certfile)
    {:ok, history_min_duration} = Application.fetch_env(:neurow, :history_min_duration)
    {:ok, max_header_length} = Application.fetch_env(:neurow, :max_header_length)

    cluster_topologies =
      Application.get_env(:neurow, :cluster_topologies, cluster_topologies_from_env_variables())

    start(%{
      public_api_port: public_api_port,
      internal_api_port: internal_api_port,
      ssl_keyfile: ssl_keyfile,
      ssl_certfile: ssl_certfile,
      max_header_length: max_header_length,
      history_min_duration: history_min_duration,
      cluster_topologies: cluster_topologies
    })
  end

  def start(%{
        public_api_port: public_api_port,
        internal_api_port: internal_api_port,
        ssl_keyfile: ssl_keyfile,
        ssl_certfile: ssl_certfile,
        max_header_length: max_header_length,
        history_min_duration: history_min_duration,
        cluster_topologies: cluster_topologies
      }) do
    Logger.info("Current host #{node()}, environment: #{@mix_env}")
    Logger.info("Starting internal API on port #{internal_api_port}")

    base_public_api_http_config = [
      port: public_api_port,
      protocol_options: [
        max_header_value_length: max_header_length,
        idle_timeout: :infinity
      ],
      transport_options: [max_connections: :infinity]
    ]

    {sse_http_scheme, public_api_http_config} =
      if ssl_keyfile != nil do
        Logger.info(
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
        Logger.info("Starting public API on port #{public_api_port} without SSL")
        {:http, base_public_api_http_config}
      end

    children =
      [
        Neurow.Configuration,
        {Phoenix.PubSub,
         name: Neurow.PubSub, options: [adapter: Phoenix.PubSub.PG2, pool_size: 10]},
        {Plug.Cowboy,
         scheme: :http, plug: Neurow.InternalApi.Endpoint, options: [port: internal_api_port]},
        {Plug.Cowboy,
         scheme: sse_http_scheme, plug: Neurow.PublicApi.Endpoint, options: public_api_http_config},
        {Plug.Cowboy.Drainer, refs: [Neurow.PublicApi.Endpoint.HTTP], shutdown: 20_000},
        {Neurow.StopListener, []},
        {Neurow.Broker.ReceiverShardManager, [history_min_duration]}
      ] ++
        Neurow.Broker.ReceiverShardManager.create_receivers() ++
        if cluster_topologies do
          [{Cluster.Supervisor, [cluster_topologies, [name: Neurow.ClusterSupervisor]]}]
        else
          []
        end

    MetricsPlugExporter.setup()
    Stats.setup()
    JOSE.json_module(:jiffy)

    opts = [strategy: :one_for_one, name: Neurow.Supervisor]

    Supervisor.start_link(children, opts)
  end

  @impl true
  def prep_stop(state) do
    Neurow.StopListener.shutdown()
    state
  end

  defp cluster_topologies_from_env_variables do
    cond do
      System.get_env("K8S_SELECTOR") && System.get_env("K8S_NAMESPACE") ->
        Logger.info(
          "Starting libcluster with K8S selector: #{System.get_env("K8S_SELECTOR")} in namespace: #{System.get_env("K8S_NAMESPACE")}"
        )

        [
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

      System.get_env("EPMD_CLUSTER_MEMBERS") ->
        Logger.info(
          "Starting libcluster with EMPD_CLUSTER_MEMBERS: #{System.get_env("EPMD_CLUSTER_MEMBERS")}"
        )

        [
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

      System.get_env("EC2_CLUSTER_TAG") && System.get_env("EC2_CLUSTER_VALUE") ->
        Logger.info(
          "Starting libcluster with EC2_CLUSTER_TAG: #{System.get_env("EC2_CLUSTER_TAG")}"
        )

        [
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

      true ->
        nil
    end
  end

  defp ec2_ip_to_nodename(list, _) when is_list(list) do
    [sname, _] = String.split(to_string(node()), "@")

    list
    |> Enum.map(fn ip ->
      :"#{sname}@ip-#{String.replace(ip, ".", "-")}"
    end)
  end
end
