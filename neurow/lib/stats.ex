defmodule Stats do
  use Prometheus.Metric

  def setup() do
    Gauge.declare(
      name: :current_connections,
      help: "SSE Open connections"
    )

    Gauge.declare(
      name: :connections,
      help: "SSE connections"
    )

    Gauge.declare(
      name: :messages,
      labels: [:kind],
      help: "SSE Messages"
    )

    Gauge.set([name: :current_connections], 0)
    Gauge.set([name: :connections], 0)
    Gauge.set([name: :messages, labels: [:received]], 0)
    Gauge.set([name: :messages, labels: [:published]], 0)
  end

  def inc_connections() do
    Gauge.inc(name: :current_connections)
    Gauge.inc(name: :connections)
  end

  def dec_connections() do
    Gauge.dec(name: :current_connections)
  end

  def inc_msg_received() do
    Gauge.inc(name: :messages, labels: [:received])
  end

  def inc_msg_published() do
    Gauge.inc(name: :messages, labels: [:published])
  end
end
