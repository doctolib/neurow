defmodule Neurow.IntegrationTest.MessageBrokeringTest do
  # require Logger

  use ExUnit.Case
  use Plug.Test
  import JwtHelper
  import SseHelper

  setup do
    Neurow.IntegrationTest.TestCluster.ensure_node_started()
    Application.ensure_all_started(:httpoison)
    HTTPoison.start()
    {:ok, cluster_state: Neurow.IntegrationTest.TestCluster.cluster_state()}
  end

  describe "topics subscriptions" do
    test "subscribers only receive messages for the topic they subscribe to", %{
      cluster_state: %{
        internal_api_ports: internal_ports,
        public_api_ports: public_ports
      }
    } do
      Enum.each(public_ports, fn public_port ->
        subscribe(public_port, "test_topic", fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 200},
                         1000,
                         "HTTP 200 on public port #{public_port}"

          assert_receive %HTTPoison.AsyncHeaders{headers: headers},
                         1000,
                         "HTTP Headers on public port #{public_port}"

          assert_headers(headers, [
            {"access-control-allow-origin", "*"},
            {"cache-control", "no-cache"},
            {"connection", "close"},
            {"content-type", "text/event-stream"},
            {"transfer-encoding", "chunked"}
          ])

          Enum.each(internal_ports, fn internal_port ->
            publish(internal_port, "other_topic", %{
              event: "other_event",
              payload: "Should not be received"
            })

            publish(internal_port, "test_topic", %{
              event: "expected_event",
              payload: "Hello on port #{internal_port}"
            })

            assert_receive(
              %HTTPoison.AsyncChunk{chunk: sse_event},
              1000,
              "SSE event from internal port #{internal_port} to public port #{public_port}"
            )

            assert_sse_event(sse_event, "expected_event", "Hello on port #{internal_port}")
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
              subscribe(public_port, "test_topic", fn ->
                assert_receive %HTTPoison.AsyncStatus{code: 200},
                               1000,
                               "HTTP 200 on public port #{public_port}"

                assert_receive %HTTPoison.AsyncHeaders{headers: headers},
                               1000,
                               "HTTP Headers on public port #{public_port}"

                assert_headers(headers, [
                  {"access-control-allow-origin", "*"},
                  {"cache-control", "no-cache"},
                  {"connection", "close"},
                  {"content-type", "text/event-stream"},
                  {"transfer-encoding", "chunked"}
                ])

                assert_receive(
                  %HTTPoison.AsyncChunk{chunk: sse_event},
                  2000,
                  "SSE event on public port #{public_port}"
                )

                assert_sse_event(sse_event, "multisubscriber_event", "Hello to all subscribers")
              end)
            end)
          end)
        end)

      # Publish one single message on the internal API
      publish(Enum.at(internal_ports, 0), "test_topic", %{
        event: "multisubscriber_event",
        payload: "Hello to all subscribers"
      })

      # Wait that all subscribe tasks end
      subscribe_tasks |> Enum.each(&Task.await/1)
    end
  end

  describe "message publishing" do
    test "delivers messages to multiple topics in one call to the internal API" do
    end

    test "delivers multiple messages to a single topic in one call to the internal API" do
    end

    test "delivers multiple messages to a mulitple topics in one call to the internal API" do
    end
  end

  defp subscribe(port, topic, assert_fn) do
    headers = [Authorization: "Bearer #{compute_jwt_token_in_req_header_public_api(topic)}"]
    async_response = HTTPoison.get!(subscribe_url(port), headers, stream_to: self())
    assert_fn.()
    :hackney.stop_async(async_response.id)
  end

  def assert_headers(headers, expected_headers) do
    expected_headers
    |> Enum.map(fn expected_header ->
      assert headers |> Enum.member?(expected_header),
             "Expecting header #{inspect(expected_header)}"
    end)
  end

  def assert_sse_event(sse_event, expected_event, expected_data, expected_id \\ nil) do
    parsed_event = parse_sse_event(sse_event)

    assert parsed_event.event == expected_event
    assert parsed_event.data == expected_data

    if expected_id != nil do
      assert parsed_event.id == expected_id
    end
  end

  defp publish_url(port), do: "http://localhost:#{port}/v1/publish"
  defp subscribe_url(port), do: "http://localhost:#{port}/v1/subscribe"

  defp publish(port, topics, messages) do
    headers = [
      Authorization: "Bearer #{compute_jwt_token_in_req_header_internal_api()}",
      "content-type": "application/json"
    ]

    payload =
      %{}
      |> Map.merge(
        case topics do
          topics when is_list(topics) ->
            %{topics: topics}

          topic when is_binary(topic) ->
            %{topic: topic}
        end
      )
      |> Map.merge(
        case messages do
          messages when is_list(messages) ->
            %{messages: messages}

          %{event: event, payload: payload, id: id} ->
            %{message: %{event: event, payload: payload, id: id}}

          %{event: event, payload: payload} ->
            %{message: %{event: event, payload: payload}}

          _ ->
            raise "Expecting %{event: event, payload: payload} or [%{event, payload, id?}]"
        end
      )

    payload_str = :jiffy.encode(payload)

    HTTPoison.post!(publish_url(port), payload_str, headers)
  end
end
