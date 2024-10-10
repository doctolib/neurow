defmodule Neurow.EcsLogFormatterTest do
  use ExUnit.Case

  test "generates ECS compliant logs with default metadata" do
    timestamp = {{2024, 10, 23}, {12, 25, 45, 123}}

    metadata = %{
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", timestamp, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log == %{
             "@timestamp" => "2024-10-23T12:25:45.123000Z",
             "log.level" => "info",
             "log.name" => "Elixir.Neurow.EcsLogFormatterTest.fake_function/4",
             "log.source" => %{
               "file" => %{
                 "name" => "test/neurow/ecs_log_formatter_test.exs",
                 "line" => 10
               }
             },
             "ecs.version" => "8.11.0",
             "message" => "Hello, world!",
             "category" => "app",
             "service" => %{
               "name" => "neurow",
               "version" => "unknown"
             }
           }
  end

  test "supports optional trace_id metadata" do
    timestamp = {{2024, 10, 23}, {12, 25, 45, 123}}

    metadata = %{
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10,
      trace_id: "1234567890"
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", timestamp, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log == %{
             "@timestamp" => "2024-10-23T12:25:45.123000Z",
             "log.level" => "info",
             "log.name" => "Elixir.Neurow.EcsLogFormatterTest.fake_function/4",
             "log.source" => %{
               "file" => %{
                 "name" => "test/neurow/ecs_log_formatter_test.exs",
                 "line" => 10
               }
             },
             "ecs.version" => "8.11.0",
             "message" => "Hello, world!",
             "category" => "app",
             "service" => %{
               "name" => "neurow",
               "version" => "unknown"
             },
             "trace.id" => "1234567890"
           }
  end

  test "supports optional error_code metadata" do
    timestamp = {{2024, 10, 23}, {12, 25, 45, 123}}

    metadata = %{
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10,
      error_code: "invalid_last_event_id"
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", timestamp, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log == %{
             "@timestamp" => "2024-10-23T12:25:45.123000Z",
             "log.level" => "info",
             "log.name" => "Elixir.Neurow.EcsLogFormatterTest.fake_function/4",
             "log.source" => %{
               "file" => %{
                 "name" => "test/neurow/ecs_log_formatter_test.exs",
                 "line" => 10
               }
             },
             "ecs.version" => "8.11.0",
             "message" => "Hello, world!",
             "category" => "app",
             "service" => %{
               "name" => "neurow",
               "version" => "unknown"
             },
             "error.code" => "invalid_last_event_id"
           }
  end
end
