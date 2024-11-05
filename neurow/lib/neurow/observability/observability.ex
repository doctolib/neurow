defmodule Neurow.Observability do
  use Prometheus.Metric

  def setup() do
    Neurow.Observability.MessageBrokerStats.setup()
    Neurow.Observability.HttpInterfacesStats.setup()
    Neurow.Observability.MetricsPlugExporter.setup()
    Neurow.Observability.SecurityStats.setup()
    Neurow.Observability.SystemStats.setup()
  end
end
