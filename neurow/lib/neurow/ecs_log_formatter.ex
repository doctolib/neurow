defmodule Neurow.EcsLogFormatter do
  # Resolved at compile time
  @revision System.get_env("GIT_COMMIT_SHA1") || "unknown"

  @ecs_version "8.11.0"

  # ECS Reference: https://www.elastic.co/guide/en/ecs/current/index.html

  def format(level, message, _timestamp, metadata) do
    # The timestamp provided in input parameter is in the system timezone,
    # but there is no clean way to get the system timezone in Elixir/Erlang to convert it to UTC and/or format it in ISO8601.
    # So we use the unix timestamp provided in the metadata to get the event datetime time in UTC
    event_datetime =
      metadata[:time]
      |> DateTime.from_unix!(:microsecond)
      |> DateTime.to_iso8601()

    {module, function, arity} = metadata[:mfa]

    %{
      "@timestamp" => event_datetime,
      "log.level" => level,
      "log.name" => "#{module}.#{function}/#{arity}",
      "log.source" => %{
        "file" => %{
          name: to_string(metadata[:file]),
          line: metadata[:line]
        }
      },
      "ecs.version" => @ecs_version,
      "message" => inline(message),
      "category" => metadata[:category] || "app",
      "service" => %{
        name: "neurow",
        version: @revision
      }
    }
    |> with_optional_attribute(metadata[:trace_id], "trace.id")
    |> with_optional_attribute(metadata[:error_code], "error.code")
    |> with_optional_attribute(metadata[:client_ip], "client.ip")
    |> with_optional_attribute(metadata[:authorization_header], "http.request.authorization")
    |> with_optional_attribute(metadata[:user_agent_header], "user_agent.original")
    |> :jiffy.encode()
    |> newline()
  end

  defp with_optional_attribute(payload, nil, _key), do: payload

  defp with_optional_attribute(payload, value, key) do
    Map.put(payload, key, inline(value))
  end

  def inline(string), do: String.replace(string, ~r/\n/, "\\n")

  defp newline(msg), do: msg <> "\n"
end
