defmodule Neurow.EcsLogFormatterTest do
  use ExUnit.Case

  test "generates ECS compliant logs with default metadata" do
    metadata = %{
      time: 1_728_556_213_722_376,
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", nil, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log == %{
             "@timestamp" => "2024-10-10T10:30:13.722376Z",
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
    metadata = %{
      time: 1_728_556_213_722_376,
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10,
      trace_id: "1234567890"
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", nil, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log == %{
             "@timestamp" => "2024-10-10T10:30:13.722376Z",
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
    metadata = %{
      time: 1_728_556_213_722_376,
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10,
      error_code: "invalid_last_event_id"
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", nil, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log == %{
             "@timestamp" => "2024-10-10T10:30:13.722376Z",
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

  test "supports optional client_ip metadata" do
    metadata = %{
      time: 1_728_556_213_722_376,
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10,
      client_ip: "127.01.02.03"
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", nil, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log == %{
             "@timestamp" => "2024-10-10T10:30:13.722376Z",
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
             "client.ip" => "127.01.02.03"
           }
  end

  test "multiline messages are inlined" do
    metadata = %{
      time: 1_728_556_213_722_376,
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello \n world!", nil, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log["message"] == "Hello \\n world!"
  end

  test "multiline trace_id are inlined" do
    metadata = %{
      time: 1_728_556_213_722_376,
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10,
      trace_id: "123\n456"
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", nil, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log["trace.id"] == "123\\n456"
  end

  test "multiline error_code are inlined" do
    metadata = %{
      time: 1_728_556_213_722_376,
      mfa: {Neurow.EcsLogFormatterTest, :fake_function, 4},
      file: "test/neurow/ecs_log_formatter_test.exs",
      line: 10,
      error_code: "bad\nerror code"
    }

    json_log =
      Neurow.EcsLogFormatter.format(:info, "Hello, world!", nil, metadata)
      |> :jiffy.decode([:return_maps])

    assert json_log["error.code"] == "bad\\nerror code"
  end
end
