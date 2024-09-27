defmodule Neurow.IntegrationTest.SseLifecycleTest do
  use ExUnit.Case

  import SseHelper
  import SseHelper.HttpSse

  alias Neurow.IntegrationTest.TestCluster

  setup do
    TestCluster.ensure_nodes_started()
    TestCluster.flush_history()
    SseHelper.HttpSse.ensure_started()
    {:ok, cluster_state: TestCluster.cluster_state()}
  end

  describe "timeout" do
    test "the SSE connection is timed-out by the server according to the server configuration", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      subscribe(first_public_port, "test_topic", fn ->
        assert_receive %HTTPoison.AsyncStatus{code: 200}
        assert_receive %HTTPoison.AsyncHeaders{headers: headers}

        assert_headers(headers, [
          {"access-control-allow-origin", "*"},
          {"cache-control", "no-cache"},
          {"connection", "close"},
          {"content-type", "text/event-stream"},
          {"transfer-encoding", "chunked"}
        ])

        assert_receive %HTTPoison.AsyncChunk{chunk: timeout_sse_event}, 4_200

        assert "timeout" == parse_sse_event(timeout_sse_event).event

        assert_receive %HTTPoison.AsyncEnd{}
      end)
    end

    test "the SSE connection is timed-out by the server based on x-sse-timeout HTTP header",
         %{
           cluster_state: %{
             public_api_ports: [first_public_port | _other_ports]
           }
         } do
      subscribe(
        first_public_port,
        "test_topic",
        fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 200}
          assert_receive %HTTPoison.AsyncHeaders{headers: headers}

          assert_headers(
            headers,
            [
              {"access-control-allow-origin", "*"},
              {"cache-control", "no-cache"},
              {"connection", "close"},
              {"content-type", "text/event-stream"},
              {"transfer-encoding", "chunked"},
              {"x-sse-timeout", "1500"}
            ]
          )

          assert_receive %HTTPoison.AsyncChunk{chunk: timeout_sse_event}, 3_000

          assert "timeout" == parse_sse_event(timeout_sse_event).event

          assert_receive %HTTPoison.AsyncEnd{}
        end,
        "x-sse-timeout": "1500"
      )
    end
  end

  describe "keepalive" do
    test "the server periodically sends a ping event to keep the connection open", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      subscribe(
        first_public_port,
        "test_topic",
        fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 200}
          assert_receive %HTTPoison.AsyncHeaders{headers: headers}

          assert_headers(
            headers,
            [
              {"access-control-allow-origin", "*"},
              {"cache-control", "no-cache"},
              {"connection", "close"},
              {"content-type", "text/event-stream"},
              {"transfer-encoding", "chunked"},
              {"x-sse-keepalive", "100"}
            ]
          )

          assert_receive %HTTPoison.AsyncChunk{chunk: ping_sse_event}, 1_500
          assert "ping" == parse_sse_event(ping_sse_event).event
        end,
        "x-sse-keepalive": "100"
      )
    end
  end
end
