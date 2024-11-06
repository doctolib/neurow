defmodule Neurow.Observability.MessageBrokerStats do
  use Prometheus.Metric

  def setup() do
    Gauge.declare(
      name: :concurrent_subscription,
      labels: [:issuer],
      help: "Amount of concurrent topic subscriptions"
    )

    Counter.declare(
      name: :subscription_lifecycle,
      labels: [:kind, :issuer],
      help: "Count subscriptions and unsubscriptions"
    )

    Summary.declare(
      name: :subscription_duration_ms,
      labels: [:issuer],
      help: "Duration of topic subscriptions"
    )

    Counter.declare(
      name: :message,
      labels: [:kind, :issuer],
      help: "Messages sent through topic subscriptions"
    )

    Counter.declare(
      name: :history_rotate,
      help: "History rotate counter"
    )

    Gauge.declare(
      name: :topic_count,
      help: "Number of topics in the message history"
    )

    Counter.reset(name: :history_rotate)

    Gauge.set([name: :topic_count], 0)

    Enum.each(Neurow.Configuration.issuers(), fn issuer ->
      Gauge.set([name: :concurrent_subscription, labels: [issuer]], 0)
      Counter.reset(name: :subscription_lifecycle, labels: [:created, issuer])
      Counter.reset(name: :subscription_lifecycle, labels: [:released, issuer])
      Counter.reset(name: :message, labels: [:published, issuer])
      Counter.reset(name: :message, labels: [:sent, issuer])
      Summary.reset(name: :subscription_duration_ms, labels: [issuer])
    end)

    Periodic.start_link(
      run: fn ->
        Gauge.set([name: :topic_count], Neurow.Broker.ReceiverShardManager.topic_count())
      end,
      every: :timer.seconds(10)
    )
  end

  def inc_subscriptions(issuer) do
    Counter.inc(name: :subscription_lifecycle, labels: [:created, issuer])
    Gauge.inc(name: :concurrent_subscription, labels: [issuer])
  end

  def dec_subscriptions(issuer, duration_ms) do
    Counter.inc(name: :subscription_lifecycle, labels: [:released, issuer])
    Gauge.dec(name: :concurrent_subscription, labels: [issuer])
    Summary.observe([name: :subscription_duration_ms, labels: [issuer]], duration_ms)
  end

  def inc_message_published(issuer) do
    Counter.inc(name: :message, labels: [:published, issuer])
  end

  def inc_message_sent(issuer) do
    Counter.inc(name: :message, labels: [:sent, issuer])
  end

  def inc_history_rotate() do
    Counter.inc(name: :history_rotate)
  end
end
