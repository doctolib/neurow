defmodule Neurow.Observability.SystemStats do
  use Prometheus.Metric

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

  defmodule ProcessesStats do
    defstruct [
      :name_or_initial_func,
      :current_func,
      process_count: 0,
      memory: 0,
      message_queue_len: 0
    ]
  end

  # Group process by name or initial function, and current function
  # Then sort by memory usage and return the top consuming processes groups
  def process_groups(result_count \\ 50) do
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
