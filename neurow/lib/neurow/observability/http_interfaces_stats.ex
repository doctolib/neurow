defmodule Neurow.Observability.HttpInterfacesStats do
  use Prometheus.Metric

  def setup() do
    Summary.declare(
      name: :http_request_duration_ms,
      labels: [:interface],
      help: "HTTP request duration"
    )

    Counter.declare(
      name: :http_request_count,
      labels: [:interface, :status],
      help: "HTTP request count"
    )

    Counter.declare(
      name: :http_request_exception_count,
      labels: [:interface, :kind],
      help: "HTTP request exception count"
    )

    Counter.declare(
      name: :http_request_early_error_count,
      labels: [:status],
      help: "HTTP request early_error count"
    )

    Summary.reset(name: :http_request_duration_ms, labels: [:public_api])
    Summary.reset(name: :http_request_duration_ms, labels: [:internal_api])

    # Please read https://github.com/beam-telemetry/cowboy_telemetry
    :telemetry.attach_many(
      "cowboy_telemetry_handler",
      [
        [:cowboy, :request, :stop],
        [:cowboy, :request, :exception],
        [:cowboy, :request, :early_error]
      ],
      &Neurow.Observability.HttpInterfacesStats.handle_event/4,
      nil
    )
  end

  def handle_event([:cowboy, :request, :stop], measurements, metadata, _config) do
    if monitor_path?(metadata[:req][:path]) do
      interface =
        case metadata[:req][:ref] do
          Neurow.PublicApi.Endpoint.HTTP -> :public_api
          Neurow.InternalApi.Endpoint.HTTP -> :internal_api
        end

      duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)
      resp_status = metadata[:resp_status]

      Counter.inc(name: :http_request_count, labels: [interface, trim_http_status(resp_status)])
      Summary.observe([name: :http_request_duration_ms, labels: [interface]], duration_ms)
    end
  end

  def handle_event([:cowboy, :request, :exception], _measurements, metadata, _config) do
    if monitor_path?(metadata[:req][:path]) do
      interface =
        case metadata[:req][:ref] do
          Neurow.PublicApi.Endpoint.HTTP -> :public_api
          Neurow.InternalApi.Endpoint.HTTP -> :internal_api
        end

      Counter.inc(name: :http_request_exception_count, labels: [interface, "#{metadata[:kind]}"])
    end
  end

  def handle_event([:cowboy, :request, :early_error], _measurements, metadata, _config) do
    if monitor_path?(metadata[:req][:path]) do
      Counter.inc(
        name: :http_request_early_error_count,
        labels: [trim_http_status(metadata[:resp_status])]
      )
    end
  end

  @unmonitored_request_paths [
    "/ping",
    "/favicon.ico",
    "/metrics"
  ]

  def unmonitored_request_paths(), do: @unmonitored_request_paths

  defp monitor_path?(path) do
    !Enum.member?(@unmonitored_request_paths, path)
  end

  defp trim_http_status(http_status) when is_binary(http_status) do
    String.split(http_status, " ") |> Enum.at(0)
  end

  defp trim_http_status(http_status) when is_integer(http_status) do
    Integer.to_string(http_status)
  end

  defp trim_http_status(http_status) when is_atom(http_status) do
    Atom.to_string(http_status)
  end
end
