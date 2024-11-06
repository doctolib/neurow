defmodule Neurow.Observability.SecurityStats do
  use Prometheus.Metric

  def setup() do
    Counter.declare(
      name: :jwt_errors,
      labels: [:interface],
      help: "JWT Errors"
    )
  end

  def inc_jwt_errors_public() do
    Counter.inc(name: :jwt_errors, labels: [:public])
  end

  def inc_jwt_errors_internal() do
    Counter.inc(name: :jwt_errors, labels: [:internal])
  end
end
