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

    Summary.reset(name: :http_request_duration_ms, labels: [:public_api])
    Summary.reset(name: :http_request_duration_ms, labels: [:internal_api])

    # Please read https://github.com/beam-telemetry/cowboy_telemetry
    :telemetry.attach_many(
      "cowboy_telemetry_handler",
      [
        [:cowboy, :request, :stop]
      ],
      &Neurow.Observability.HttpInterfacesStats.handle_event/4,
      nil
    )
  end

  def handle_event([:cowboy, :request, :stop], measurements, metadata, _config) do
    endpoint =
      case metadata[:req][:ref] do
        Neurow.PublicApi.Endpoint.HTTP -> :public_api
        Neurow.InternalApi.Endpoint.HTTP -> :internal_api
      end

    duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)
    resp_status = metadata[:resp_status]

    Counter.inc(name: :http_request_count, labels: [endpoint, resp_status])
    Summary.observe([name: :http_request_duration_ms, labels: [endpoint]], duration_ms)
  end
end
