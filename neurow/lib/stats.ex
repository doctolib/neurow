defmodule Neurow.Stats do
  use Prometheus.Metric

  def setup() do
    Neurow.Stats.MessageBroker.setup()
    Neurow.Stats.HttpInterfaces.setup()
    Neurow.Stats.Security.setup()
    Neurow.Stats.System.setup()
  end

  defmodule MessageBroker do
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

  defmodule HttpInterfaces do
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
        &Neurow.Stats.HttpInterfaces.handle_event/4,
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

  defmodule Security do
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

  defmodule System do
    def setup() do
      Gauge.declare(
        name: :memory_usage,
        help: "Memory usage"
      )

      Boolean.declare(
        name: :stopping,
        help: "The node is currently stopping"
      )

      Gauge.set([name: :memory_usage], 0)
      Boolean.set([name: :stopping], false)

      Periodic.start_link(
        run: fn -> Gauge.set([name: :memory_usage], :recon_alloc.memory(:usage)) end,
        every: :timer.seconds(10)
      )
    end

    def report_shutdown() do
      Boolean.set([name: :stopping], true)
    end
  end

  defmodule Processes do
    defmodule ProcessesStats do
      defstruct [
        :name_or_initial_func,
        :current_func,
        process_count: 0,
        memory: 0,
        message_queue_len: 0
      ]
    end

    def grouping_stats(result_count \\ 40) do
      Process.list()
      |> Enum.reduce(%{}, fn pid, acc ->
        {name_or_initial_func, current_func} = grouping_attributes(pid)

        process_info =
          Process.info(pid, [
            :memory,
            :message_queue_len
          ])

        current_stats =
          acc[{name_or_initial_func, current_func}] ||
            %ProcessesStats{
              name_or_initial_func: name_or_initial_func,
              current_func: current_func
            }

        process_count = current_stats.process_count + 1
        memory = current_stats.memory + (process_info[:memory] || 0)

        message_queue_len =
          current_stats.message_queue_len + (process_info[:message_queue_len] || 0)

        Map.put(acc, {name_or_initial_func, current_func}, %ProcessesStats{
          name_or_initial_func: name_or_initial_func,
          process_count: process_count,
          current_func: current_func,
          memory: memory,
          message_queue_len: message_queue_len
        })
      end)
      |> Map.values()
      |> Enum.sort(&(&1.memory > &2.memory))
      |> Enum.take(result_count)
    end

    defp mfa_to_string({module, function, arity}) do
      "#{module}:#{function}/#{arity}"
    end

    defp grouping_attributes(pid) do
      name_or_initial_func =
        case Process.info(pid, [:registered_name, :dictionary, :initial_call]) do
          [{:registered_name, name} | _rest] when is_atom(name) ->
            name

          [{:registered_name, [first_name | _other_names]}, _rest] ->
            first_name

          [
            {:registered_name, []},
            {:dictionary, [{:"$initial_call", initial_call} | _rest_dictionary]} | _rest
          ] ->
            mfa_to_string(initial_call)

          [
            {:registered_name, []},
            {:dictionary, _rest_dictionary},
            {:initial_call, initial_call}
          ] ->
            mfa_to_string(initial_call)

          _ ->
            :undefined
        end

      case Process.info(pid, :current_function) do
        {:current_function, current_function} ->
          {name_or_initial_func, mfa_to_string(current_function)}

        nil ->
          {name_or_initial_func, :undefined}
      end
    end
  end
end
