defmodule Neurow.IntegrationTest.MessageHistoryTest do
  use ExUnit.Case

  alias Neurow.IntegrationTest.TestCluster

  import SseHelper
  import SseHelper.HttpSse
  import JwtHelper

  setup do
    TestCluster.ensure_nodes_started()
    TestCluster.flush_history()
    SseHelper.HttpSse.ensure_started()
    {:ok, cluster_state: TestCluster.cluster_state()}
  end

  describe "Fetch history on SSE subscription" do
    setup %{
      cluster_state: %{
        internal_api_ports: [first_internal_port | _other_internal_ports]
      }
    } do
      publish(
        first_internal_port,
        "test_topic",
        Enum.map(1..5, fn index ->
          %{
            timestamp: index,
            event: "test_event",
            payload: "Message #{index}"
          }
        end)
      )

      :ok
    end

    test "do not return the topic history if Last-Event-Id is not set", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      subscribe(first_public_port, "test_topic", fn ->
        assert_receive %HTTPoison.AsyncStatus{code: 200}
        assert_receive %HTTPoison.AsyncHeaders{headers: headers}

        assert_headers(headers, [
          {"access-control-allow-origin", "*"},
          {"cache-control", "no-cache, no-store"},
          {"connection", "close"},
          {"content-type", "text/event-stream"},
          {"transfer-encoding", "chunked"}
        ])

        assert_no_more_chunk()
      end)
    end

    test "return a 400 error if Last-Event-Id is not an number", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      subscribe(
        first_public_port,
        "test_topic",
        fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 400}
          assert_receive %HTTPoison.AsyncHeaders{headers: headers}

          assert_headers(headers, [
            {"access-control-allow-origin", "*"},
            {"cache-control", "no-cache, no-store"},
            {"connection", "close"},
            {"content-type", "text/event-stream"},
          ])

          assert_receive %HTTPoison.AsyncChunk{chunk: body}

          json_event = parse_sse_json_event(body)

          assert json_event.event == "neurow_error_400"

          assert json_event.data ==
                   %{
                     "errors" => [
                       %{
                         "error_code" => "invalid_last_event_id",
                         "error_message" => "Wrong value for last-event-id"
                       }
                     ]
                   }

          assert_receive %HTTPoison.AsyncEnd{}
        end,
        "last-event-id": "foo"
      )
    end

    test "do not return any message if the topic history is empty", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      subscribe(
        first_public_port,
        "empty_topic",
        fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 200}

          assert_receive %HTTPoison.AsyncHeaders{headers: headers}

          assert_headers(headers, [
            {"access-control-allow-origin", "*"},
            {"cache-control", "no-cache, no-store"},
            {"connection", "close"},
            {"content-type", "text/event-stream"},
            {"transfer-encoding", "chunked"}
          ])

          assert_no_more_chunk()
        end,
        "last-event-id": "0"
      )
    end

    test "return the full history if Last-Event-Id is set to 0", %{
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

          assert_headers(headers, [
            {"access-control-allow-origin", "*"},
            {"cache-control", "no-cache, no-store"},
            {"connection", "close"},
            {"content-type", "text/event-stream"},
            {"transfer-encoding", "chunked"}
          ])

          Enum.each(1..5, fn index ->
            assert_receive(%HTTPoison.AsyncChunk{chunk: sse_event})
            assert_sse_event(sse_event, "test_event", "Message #{index}", "#{index}")
          end)

          assert_no_more_chunk()
        end,
        "last-event-id": "0"
      )
    end

    test "only returns messages more recent than the Last-Event-Id", %{
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

          assert_headers(headers, [
            {"access-control-allow-origin", "*"},
            {"cache-control", "no-cache, no-store"},
            {"connection", "close"},
            {"content-type", "text/event-stream"},
            {"transfer-encoding", "chunked"}
          ])

          Enum.each(3..5, fn index ->
            assert_receive(%HTTPoison.AsyncChunk{chunk: sse_event})
            assert_sse_event(sse_event, "test_event", "Message #{index}", "#{index}")
          end)

          assert_no_more_chunk()
        end,
        "last-event-id": "2"
      )
    end
  end

  describe "Fetch the history of a topic on the internal API" do
    test "The history endpoint returns the full history on all nodes", %{
      cluster_state: %{
        internal_api_ports: internal_ports
      }
    } do
      first_internal_port = Enum.at(internal_ports, 0)

      expected_history =
        Enum.map(1..5, fn index ->
          %{
            "timestamp" => index,
            "event" => "test_event",
            "payload" => "Message #{index}"
          }
        end)

      # Publish messages on the first node
      publish(
        first_internal_port,
        "test_topic",
        expected_history
      )

      request_headers = [
        Authorization: "Bearer #{compute_jwt_token_in_req_header_internal_api()}",
        "content-type": "application/json"
      ]

      # Then iterate on each node to fetch the history on the internal API
      Enum.each(internal_ports, fn internal_port ->
        %HTTPoison.Response{body: body, headers: response_headers} =
          HTTPoison.get!(
            "http://localhost:#{first_internal_port}/history/test_issuer1-test_topic",
            request_headers
          )

        assert_headers(response_headers, [
          {"content-type", "application/json"}
        ])

        returned_history = :jiffy.decode(body, [:return_maps])

        assert returned_history == expected_history, "History on internal port #{internal_port}"
      end)
    end
  end

  describe "messages retention" do
    setup %{
      cluster_state: %{
        internal_api_ports: [first_internal_port | _other_ports]
      }
    } do
      # The retention policy is set to 3 seconds in Neurow.IntegrationTest.TestCluster
      # So, sleep times are added to ensure that message expires

      # First chunk of messages
      publish(
        first_internal_port,
        "test_topic",
        Enum.map(1..3, fn index ->
          %{
            event: "test_event",
            payload: "First chunk #{index}"
          }
        end)
      )

      # Wait a bit
      Process.sleep(3000)

      # Second chunk of messages
      publish(
        first_internal_port,
        "test_topic",
        Enum.map(1..3, fn index ->
          %{
            event: "test_event",
            payload: "Second chunk #{index}"
          }
        end)
      )

      # Wait a bit more so the first chunk of messages should be expired
      Process.sleep(3000)
      :ok
    end

    test "messages are not returned on the history endpoint of the internal API after expiration",
         %{
           cluster_state: %{
             internal_api_ports: internal_ports
           }
         } do
      request_headers = [
        Authorization: "Bearer #{compute_jwt_token_in_req_header_internal_api()}",
        "content-type": "application/json"
      ]

      # Fetch the history from each node and assert its content
      Enum.each(internal_ports, fn internal_port ->
        %HTTPoison.Response{body: body, headers: response_headers} =
          HTTPoison.get!(
            "http://localhost:#{internal_port}/history/test_issuer1-test_topic",
            request_headers
          )

        assert_headers(response_headers, [
          {"content-type", "application/json"}
        ])

        returned_history = :jiffy.decode(body, [:return_maps])

        history_payloads =
          returned_history
          |> Enum.map(fn message -> message["payload"] end)
          |> Enum.sort()

        assert history_payloads == ["Second chunk 1", "Second chunk 2", "Second chunk 3"]
      end)
    end

    test "messages are not sent throught the SSE connection after expiration", %{
      cluster_state: %{
        public_api_ports: public_ports
      }
    } do
      Enum.each(public_ports, fn public_ports ->
        subscribe(
          public_ports,
          "test_topic",
          fn ->
            assert_receive %HTTPoison.AsyncStatus{code: 200}

            assert_receive %HTTPoison.AsyncHeaders{}

            history_payloads =
              Enum.map(1..3, fn _index ->
                assert_receive %HTTPoison.AsyncChunk{chunk: sse_event}
                parse_sse_event(sse_event).data
              end)
              |> Enum.sort()

            assert_no_more_chunk()

            assert history_payloads == ["Second chunk 1", "Second chunk 2", "Second chunk 3"]
          end,
          "last-event-id": "0"
        )
      end)
    end
  end
end
