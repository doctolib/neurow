defmodule Neurow.IntegrationTest.MessageBrokeringTest do
  # require Logger

  use ExUnit.Case
  use Plug.Test

  import SseHelper
  alias SseHelper.HttpSse

  setup do
    Neurow.IntegrationTest.TestCluster.ensure_node_started()
    HttpSse.ensure_started()
    {:ok, cluster_state: Neurow.IntegrationTest.TestCluster.cluster_state()}
  end

  describe "topics subscriptions" do
    test "subscribers only receive messages for the topic they subscribe to", %{
      cluster_state: %{
        internal_api_ports: internal_ports,
        public_api_ports: public_ports
      }
    } do
      # Nested loop on all public ports and internal ports to ensure that messages
      # can be forwarded from all nodes to all nodes in the cluster
      Enum.each(public_ports, fn public_port ->
        HttpSse.subscribe(public_port, "test_topic", fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 200},
                         1_000,
                         "HTTP 200 on public port #{public_port}"

          assert_receive %HTTPoison.AsyncHeaders{headers: headers},
                         1_000,
                         "HTTP Headers on public port #{public_port}"

          HttpSse.assert_headers(headers, [
            {"access-control-allow-origin", "*"},
            {"cache-control", "no-cache"},
            {"connection", "close"},
            {"content-type", "text/event-stream"},
            {"transfer-encoding", "chunked"}
          ])

          Enum.each(internal_ports, fn internal_port ->
            HttpSse.publish(internal_port, "other_topic", %{
              event: "other_event",
              payload: "Should not be received"
            })

            HttpSse.publish(internal_port, "test_topic", %{
              event: "expected_event",
              payload: "Hello from #{internal_port}"
            })

            assert_receive(
              %HTTPoison.AsyncChunk{chunk: sse_event},
              1_000,
              "SSE event from internal port #{internal_port} to public port #{public_port}"
            )

            assert_sse_event(sse_event, "expected_event", "Hello from #{internal_port}")
          end)
        end)
      end)
    end

    test "messages are delivered to all subscribers of a topic", %{
      cluster_state: %{
        internal_api_ports: internal_ports,
        public_api_ports: public_ports
      }
    } do
      # Starts 3 subscribers on each nodes
      subscribe_tasks =
        Enum.flat_map(public_ports, fn public_port ->
          Enum.map(1..3, fn _index ->
            Task.async(fn ->
              HttpSse.subscribe(public_port, "test_topic", fn ->
                assert_receive %HTTPoison.AsyncStatus{code: 200},
                               1_000,
                               "HTTP 200 on public port #{public_port}"

                assert_receive %HTTPoison.AsyncHeaders{headers: headers},
                               1_000,
                               "HTTP Headers on public port #{public_port}"

                assert_receive(
                  %HTTPoison.AsyncChunk{chunk: sse_event},
                  2_000,
                  "SSE event on public port #{public_port}"
                )

                HttpSse.assert_headers(headers, [
                  {"access-control-allow-origin", "*"},
                  {"cache-control", "no-cache"},
                  {"connection", "close"},
                  {"content-type", "text/event-stream"},
                  {"transfer-encoding", "chunked"}
                ])

                assert_sse_event(sse_event, "multisubscriber_event", "Hello to all subscribers")
              end)
            end)
          end)
        end)

      # Wait that subscribers are actually attached before publishing the message
      :timer.sleep(1_000)

      # Then publish one single message on the internal API of the first node
      HttpSse.publish(Enum.at(internal_ports, 0), "test_topic", %{
        event: "multisubscriber_event",
        payload: "Hello to all subscribers"
      })

      # Wait that all subscribe tasks end
      subscribe_tasks |> Enum.each(fn task -> Task.await(task, 4_000) end)
    end
  end

  describe "message publishing" do
    test "delivers messages to multiple topics in one call to the internal API", %{
      cluster_state: %{
        internal_api_ports: internal_ports,
        public_api_ports: public_ports
      }
    } do
      # Start one subscriber on each node on its own topic
      subscribe_tasks =
        Enum.map(public_ports, fn public_port ->
          Task.async(fn ->
            HttpSse.subscribe(public_port, "test_topic:#{public_port}", fn ->
              assert_receive %HTTPoison.AsyncStatus{code: 200},
                             1_000,
                             "HTTP 200 on public port #{public_port}"

              assert_receive %HTTPoison.AsyncHeaders{},
                             1_000,
                             "HTTP Headers on public port #{public_port}"

              Enum.each(internal_ports, fn internal_port ->
                # Expect to receive a message published on each node
                assert_receive(
                  %HTTPoison.AsyncChunk{chunk: sse_event},
                  2_000,
                  "SSE event on public port #{public_port} from #{internal_port}"
                )

                assert_sse_event(sse_event, "multitopic_event", "Hello from #{internal_port}")
              end)
            end)
          end)
        end)

      # Wait that subscribers are actually attached before publishing the message
      :timer.sleep(1_000)

      # Then, send messages on each node on each subscribed topic
      Enum.each(internal_ports, fn internal_port ->
        HttpSse.publish(
          internal_port,
          Enum.map(public_ports, fn public_port -> "test_topic:#{public_port}" end),
          %{
            event: "multitopic_event",
            payload: "Hello from #{internal_port}"
          }
        )
      end)

      # Wait that all subscribe tasks end
      subscribe_tasks |> Enum.each(fn task -> Task.await(task, 4_000) end)
    end

    test "delivers multiple messages to a single topic in one call to the internal API" do
    end

    test "delivers multiple messages to a mulitple topics in one call to the internal API" do
    end
  end
end
