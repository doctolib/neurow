defmodule Neurow.IntegrationTest.MessageHistoryTest do
  use ExUnit.Case
  use Plug.Test

  alias Neurow.IntegrationTest.TestCluster

  import SseHelper
  alias SseHelper.HttpSse

  setup do
    TestCluster.ensure_node_started()
    TestCluster.flush_history()
    HttpSse.ensure_started()
    {:ok, cluster_state: TestCluster.cluster_state()}
  end

  describe "Fetch history on SSE subscription" do
    test "do not get the topic history if Last-Event-Id is not set", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      HttpSse.subscribe(first_public_port, "test_topic", fn ->
        assert_receive %HTTPoison.AsyncStatus{code: 200}

        assert_receive %HTTPoison.AsyncHeaders{headers: headers}

        HttpSse.assert_headers(headers, [
          {"access-control-allow-origin", "*"},
          {"cache-control", "no-cache"},
          {"connection", "close"},
          {"content-type", "text/event-stream"},
          {"transfer-encoding", "chunked"}
        ])

        HttpSse.assert_no_more_chunk()
      end)
    end

    test "get a 400 error if Last-Event-Id is not an number", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      HttpSse.subscribe(
        first_public_port,
        "test_topic",
        fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 400}

          assert_receive %HTTPoison.AsyncHeaders{headers: headers}

          HttpSse.assert_headers(headers, [
            {"access-control-allow-origin", "*"},
            {"cache-control", "no-cache"},
            {"connection", "close"},
            {"content-type", "text/event-stream"},
            {"transfer-encoding", "chunked"}
          ])

          assert_receive %HTTPoison.AsyncChunk{chunk: error_sse_event}

          json_event = parse_sse_json_event(error_sse_event)

          assert json_event.event == "neurow_error_bad_request"

          assert json_event.data == %{
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

    test "do not get any message if the topic history is empty", %{
      cluster_state: %{
        public_api_ports: [first_public_port | _other_ports]
      }
    } do
      HttpSse.subscribe(
        first_public_port,
        "test_topic",
        fn ->
          assert_receive %HTTPoison.AsyncStatus{code: 200}

          assert_receive %HTTPoison.AsyncHeaders{headers: headers}

          HttpSse.assert_headers(headers, [
            {"access-control-allow-origin", "*"},
            {"cache-control", "no-cache"},
            {"connection", "close"},
            {"content-type", "text/event-stream"},
            {"transfer-encoding", "chunked"}
          ])

          HttpSse.assert_no_more_chunk()
        end,
        "last-event-id": "0"
      )
    end

    test "get the full history if Last-Event-Id is set to 0" do
    end

    test "only get messages most recent than the Last-Event-Id" do
    end
  end

  describe "Messages retention" do
  end

  describe "Get history on the internal API" do
  end
end
