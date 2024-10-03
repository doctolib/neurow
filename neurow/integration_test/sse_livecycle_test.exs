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
  end

  describe "keepalive" do
    test "the server periodically sends a ping event to keep the connection open", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      override_keepalive(100)

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
        end
      )
    end
  end

  describe "node shutdown" do
    setup do
      {node_name, public_api_port, _internal_api_port} = TestCluster.start_new_node()

      on_exit(fn ->
        TestCluster.shutdown_node(node_name)
      end)

      {:ok, node_name: node_name, public_api_port: public_api_port}
    end

    test "the client receives a 'shutdown' event when the node it is connected to is shutdowned",
         %{
           node_name: node_name,
           public_api_port: public_api_port
         } do
      Task.async(fn ->
        subscribe(public_api_port, "test_topic", fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 200}
          assert_receive %HTTPoison.AsyncHeaders{}

          assert_receive %HTTPoison.AsyncChunk{chunk: shutdown_sse_event}, 5_000

          assert "reconnect" == parse_sse_event(shutdown_sse_event).event

          assert_receive %HTTPoison.AsyncEnd{}
        end)
      end)

      TestCluster.shutdown_node(node_name)
    end
  end

  def override_timeout(timeout) do
    {:ok, default_timeout} = Application.fetch_env(:neurow, :sse_timeout)
    TestCluster.update_sse_timeout(timeout)

    on_exit(fn ->
      TestCluster.update_sse_timeout(default_timeout)
    end)
  end

  def override_keepalive(keepalive) do
    {:ok, default_keepalive} = Application.fetch_env(:neurow, :sse_keepalive)
    TestCluster.update_sse_keepalive(keepalive)

    on_exit(fn ->
      TestCluster.update_sse_keepalive(default_keepalive)
    end)
  end
end
