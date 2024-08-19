defmodule Stats do
  use Prometheus.Metric

  def setup() do
    Gauge.declare(
      name: :user_running,
      help: "User running"
    )

    Gauge.declare(
      name: :messages,
      labels: [:kind, :status],
      help: "Messages counter"
    )

    Gauge.declare(
      name: :users,
      labels: [:status],
      help: "User counter"
    )

    Summary.new(
      name: :propagation_delay,
      help: "Propagation delay"
    )

    Gauge.set([name: :user_running], 0)
    Gauge.set([name: :users, labels: [:ok]], 0)
    Gauge.set([name: :users, labels: [:error]], 0)
    Gauge.set([name: :messages, labels: [:received, :ok]], 0)
    Gauge.set([name: :messages, labels: [:received, :error]], 0)
    Gauge.set([name: :messages, labels: [:received, :timeout]], 0)
    Gauge.set([name: :messages, labels: [:received, :http_error]], 0)
    Gauge.set([name: :messages, labels: [:published, :ok]], 0)
    Gauge.set([name: :messages, labels: [:published, :error]], 0)

    Periodic.start_link(
      run: fn -> Summary.reset(name: :propagation_delay) end,
      every: :timer.seconds(10)
    )
  end

  def inc_user_running() do
    Gauge.inc(name: :user_running)
  end

  def dec_user_running() do
    Gauge.dec(name: :user_running)
  end

  def inc_msg_received_ok() do
    Gauge.inc(name: :messages, labels: [:received, :ok])
  end

  def inc_msg_received_error() do
    Gauge.inc(name: :messages, labels: [:received, :error])
  end

  def inc_msg_received_unexpected_message() do
    Gauge.inc(name: :messages, labels: [:received, :unexpected_message])
  end

  def inc_msg_received_http_error() do
    Gauge.inc(name: :messages, labels: [:received, :http_error])
  end

  def inc_msg_received_timeout() do
    Gauge.inc(name: :messages, labels: [:received, :timeout])
  end

  def inc_user_ok() do
    Gauge.inc(name: :users, labels: [:ok])
  end

  def inc_user_error() do
    Gauge.inc(name: :users, labels: [:error])
  end

  def inc_msg_published_ok() do
    Gauge.inc(name: :messages, labels: [:published, :ok])
  end

  def inc_msg_published_error() do
    Gauge.inc(name: :messages, labels: [:published, :error])
  end

  def observe_propagation(delay) do
    Summary.observe([name: :propagation_delay], delay)
  end
end
