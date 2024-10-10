defmodule Neurow.EcsLogFormatter do
  # Resolved at compile time
  @revision System.get_env("GIT_COMMIT_SHA1") || "unknown"

  # ECS Reference: https://www.elastic.co/guide/en/ecs/current/index.html

  def format(level, message, timestamp, metadata) do
    {{year, month, day}, {hour, minute, second, millisecond}} = timestamp
    {:ok, date} = Date.new(year, month, day)
    {:ok, time} = Time.new(hour, minute, second, millisecond * 1000)
    {:ok, datetime} = DateTime.new(date, time)

    {module, function, arity} = metadata[:mfa]

    %{
      "@timestamp" => datetime |> DateTime.to_iso8601(),
      "log.level" => level,
      "log.name" => "#{module}.#{function}/#{arity}",
      "log.source" => %{
        "file" => %{
          name: to_string(metadata[:file]),
          line: metadata[:line]
        }
      },
      "ecs.version" => "8.11.0",
      "message" => message,
      "category" => metadata[:category] || "app",
      "service" => %{
        name: "neurow",
        version: @revision
      }
    }
    |> with_optional_attribute(metadata[:trace_id], "trace.id")
    |> with_optional_attribute(metadata[:error_code], "error.code")
    |> :jiffy.encode()
    |> new_line()
  end

  defp with_optional_attribute(payload, attribute, attribute_name) do
    if attribute,
      do: Map.put(payload, attribute_name, attribute),
      else: payload
  end

  defp new_line(msg), do: "#{msg}\n"
end
