defmodule Stats do
  use Prometheus.Metric

  def setup() do
    Gauge.declare(
      name: :current_connections,
      help: "SSE Open connections"
    )

    Gauge.declare(
      name: :connections,
      labels: [:kind],
      help: "SSE connections"
    )

    Gauge.declare(
      name: :messages,
      labels: [:kind],
      help: "SSE Messages"
    )

    Gauge.declare(
      name: :jwt_errors,
      labels: [:kind],
      help: "JWT Errors"
    )

    Gauge.declare(
      name: :history_rotate,
      help: "History rotate counter"
    )

    Gauge.declare(
      name: :memory_usage,
      help: "Memory usage"
    )

    Gauge.set([name: :current_connections], 0)
    Gauge.set([name: :connections, labels: [:created]], 0)
    Gauge.set([name: :connections, labels: [:released]], 0)
    Gauge.set([name: :jwt_errors, labels: [:public]], 0)
    Gauge.set([name: :jwt_errors, labels: [:internal]], 0)
    Gauge.set([name: :messages, labels: [:received]], 0)
    Gauge.set([name: :messages, labels: [:published]], 0)
    Gauge.set([name: :history_rotate], 0)
  end

  def inc_connections() do
    Gauge.inc(name: :connections, labels: [:created])
    Gauge.inc(name: :current_connections)
  end

  def dec_connections() do
    Gauge.inc(name: :connections, labels: [:released])
    Gauge.dec(name: :current_connections)
  end

  def inc_msg_received() do
    Gauge.inc(name: :messages, labels: [:received])
  end

  def inc_msg_published() do
    Gauge.inc(name: :messages, labels: [:published])
  end

  def inc_jwt_errors_public() do
    Gauge.inc(name: :jwt_errors, labels: [:public])
  end

  def inc_jwt_errors_internal() do
    Gauge.inc(name: :jwt_errors, labels: [:internal])
  end

  def inc_history_rotate() do
    Gauge.inc(name: :history_rotate)
  end

  def set_memory_usage(value) do
    Gauge.set([name: :memory_usage], value)
  end
end
