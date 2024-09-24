defmodule Neurow.PublicApi.EndpointTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper
  import SseHelper

  import SseHelper.PlugSse

  describe "authentication" do
    test "denies access if no JWT token is provided" do
      conn =
        conn(:get, "/v1/subscribe")

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 403}
        assert_receive {:chunk, body}

        sse_event = parse_sse_json_event(body)

        assert sse_event.event == "neurow_error_forbidden"

        assert sse_event.data == %{
                 "errors" => [
                   %{
                     "error_code" => "invalid_authorization_header",
                     "error_message" => "Invalid authorization header"
                   }
                 ]
               }
      end)
    end

    test "denies access if an invalid JWT token is provided" do
      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header("authorization", "Bearer bad_token")

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 403}
        assert_receive {:chunk, body}
        event = parse_sse_json_event(body)

        assert event.event == "neurow_error_forbidden"

        assert event.data == %{
                 "errors" => [
                   %{
                     "error_code" => "invalid_jwt_token",
                     "error_message" => "Invalid JWT token"
                   }
                 ]
               }
      end)
    end

    test "allows access if a valid JWT token is provided" do
      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("foo56")}"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}
      end)
    end
  end

  describe "messaging" do
    test "transmits messages for the subscribed topic" do
      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}

        publish_message("test_issuer1-test_topic1", 1234, "First message")
        publish_message("test_issuer1-other_topic", 1234, "This message is not expected")
        publish_message("test_issuer1-test_topic1", 4567, "Second message")

        assert_receive {:chunk, first_event}
        assert_receive {:chunk, second_event}

        assert parse_sse_event(first_event) == %{
                 id: "1234",
                 event: "test-event",
                 data: "First message"
               }

        assert parse_sse_event(second_event) == %{
                 id: "4567",
                 event: "test-event",
                 data: "Second message"
               }
      end)
    end
  end

  describe "history" do
    setup do
      GenServer.call(Neurow.Broker.ReceiverShardManager, {:rotate})
      GenServer.call(Neurow.Broker.ReceiverShardManager, {:rotate})
      Process.sleep(20)
      :ok
    end

    test "returns a bad request error if the Last-Event_Id header is not an integer" do
      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )
        |> put_req_header(
          "last-event-id",
          "bad_message_id"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 400}
        assert_receive {:chunk, body}
        event = parse_sse_json_event(body)

        assert event.event == "neurow_error_bad_request"

        assert event.data == %{
                 "errors" => [
                   %{
                     "error_code" => "invalid_last_event_id",
                     "error_message" => "Wrong value for last-event-id"
                   }
                 ]
               }

        assert_receive {:DOWN, _reference, :process, _pid, :normal}, 2_000
      end)
    end

    test "does not return any history is the last-event-id header is not set" do
      publish_message("test_issuer1-test_topic1", 2, "Message ID2")
      publish_message("test_issuer1-test_topic1", 5, "Message ID5")
      publish_message("test_issuer1-test_topic1", 6, "Message ID6")
      publish_message("test_issuer1-other_topic", 7, "This message is not expected")
      publish_message("test_issuer1-test_topic1", 8, "Message ID8")

      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}

        assert_no_more_chunk()
      end)
    end

    test "does not return any message if the last-event-id is set but the topic does not have any history" do
      publish_message("test_issuer1-other_topic", 7, "This message is not expected")

      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )
        |> put_req_header(
          "last-event-id",
          "3"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}

        assert_no_more_chunk()
      end)
    end

    test "returns the full history if the last-event-id is lower than the oldest message" do
      publish_message("test_issuer1-test_topic1", 1, "Message ID1")
      publish_message("test_issuer1-test_topic1", 5, "Message ID5")
      publish_message("test_issuer1-test_topic1", 6, "Message ID6")
      publish_message("test_issuer1-other_topic", 7, "This message is not expected")
      publish_message("test_issuer1-test_topic1", 8, "Message ID8")

      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )
        |> put_req_header(
          "last-event-id",
          "0"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}

        assert_receive {:chunk, message_id2}
        assert_receive {:chunk, message_id5}
        assert_receive {:chunk, message_id6}
        assert_receive {:chunk, message_id8}

        event_id2 = parse_sse_event(message_id2)
        event_id5 = parse_sse_event(message_id5)
        event_id6 = parse_sse_event(message_id6)
        event_id8 = parse_sse_event(message_id8)

        assert event_id2.id == "1"
        assert event_id5.id == "5"
        assert event_id6.id == "6"
        assert event_id8.id == "8"

        assert event_id2.data == "Message ID1"
        assert event_id5.data == "Message ID5"
        assert event_id6.data == "Message ID6"
        assert event_id8.data == "Message ID8"

        assert_no_more_chunk()
      end)
    end

    test "returns an empty history if the last-event-id is higher or equal to the latest message" do
      publish_message("test_issuer1-test_topic1", 1, "Message ID1")
      publish_message("test_issuer1-test_topic1", 5, "Message ID5")
      publish_message("test_issuer1-test_topic1", 6, "Message ID6")
      publish_message("test_issuer1-other_topic", 7, "This message is not expected")
      publish_message("test_issuer1-test_topic1", 8, "Message ID8")

      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )
        |> put_req_header(
          "last-event-id",
          "8"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}
        assert_no_more_chunk()
      end)
    end

    test "return a partial history if the last-event-id is in the middle of the available messages" do
      publish_message("test_issuer1-test_topic1", 1, "Message ID1")
      publish_message("test_issuer1-test_topic1", 5, "Message ID5")
      publish_message("test_issuer1-test_topic1", 6, "Message ID6")
      publish_message("test_issuer1-other_topic", 7, "This message is not expected")
      publish_message("test_issuer1-test_topic1", 8, "Message ID8")

      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )
        |> put_req_header(
          "last-event-id",
          "5"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}

        assert_receive {:chunk, message_id6}
        assert_receive {:chunk, message_id8}

        assert parse_sse_event(message_id6) == %{
                 id: "6",
                 event: "test-event",
                 data: "Message ID6"
               }

        assert parse_sse_event(message_id8) == %{
                 id: "8",
                 event: "test-event",
                 data: "Message ID8"
               }
      end)
    end

    test "returns the requested history, then returns ongoing messages" do
      publish_message("test_issuer1-test_topic1", 1, "Message ID1")
      publish_message("test_issuer1-test_topic1", 2, "Message ID5")
      publish_message("test_issuer1-test_topic1", 6, "Message ID6")
      publish_message("test_issuer1-other_topic", 7, "This message is not expected")
      publish_message("test_issuer1-test_topic1", 8, "Message ID8")

      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )
        |> put_req_header(
          "last-event-id",
          "6"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}

        assert_receive {:chunk, message_id8}

        assert parse_sse_event(message_id8) == %{
                 id: "8",
                 event: "test-event",
                 data: "Message ID8"
               }

        publish_message("test_issuer1-other_topic", 50, "This message is not expected")
        publish_message("test_issuer1-test_topic1", 42, "Message ID42")

        assert_receive {:chunk, message_id42}

        assert parse_sse_event(message_id42) == %{
                 id: "42",
                 event: "test-event",
                 data: "Message ID42"
               }
      end)
    end
  end

  describe "SSE lifecycle" do
    test "the client is disconnected after inactivity" do
      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )
        |> put_req_header("x-sse-timeout", "500")

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}
        assert_receive {:DOWN, _reference, :process, _pid, :normal}, 2_000
      end)
    end

    test "a ping event is sent every 'keep_alive' interval" do
      conn =
        conn(:get, "/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )
        |> put_req_header("x-sse-keepalive", "500")

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}
        assert_receive {:chunk, body_1}, 2_000
        event_1 = parse_sse_event(body_1)

        assert event_1.event == "ping"

        assert_receive {:chunk, body_2}, 2_000
        event_2 = parse_sse_event(body_2)

        assert event_2.event == "ping"
      end)
    end
  end

  describe "preflight requests" do
    test "denies access if the request does not contain the Origin headers" do
      response =
        Neurow.PublicApi.Endpoint.call(
          conn(:options, "/v1/subscribe")
          |> put_req_header("access-control-request-headers", "authorization"),
          []
        )

      assert response.status == 400
    end

    test "denies access if the request does not contain the Access-Control-Request-Headers headers" do
      response =
        Neurow.PublicApi.Endpoint.call(
          conn(:options, "/v1/subscribe")
          |> put_req_header("origin", "https://www.doctolib.fr"),
          []
        )

      assert response.status == 400
    end

    test "denies access if the request Origin is not part of the list of allowed origins" do
      response =
        Neurow.PublicApi.Endpoint.call(
          conn(:options, "/v1/subscribe")
          |> put_req_header("origin", "https://www.unauthorized-domain.com")
          |> put_req_header("access-control-request-headers", "authorization"),
          []
        )

      assert response.status == 400
    end

    test "allow access if the Origin is part of the list of allowed origins" do
      response =
        Neurow.PublicApi.Endpoint.call(
          conn(:options, "/v1/subscribe")
          |> put_req_header("origin", "https://www.doctolib.fr")
          |> put_req_header("access-control-request-headers", "authorization"),
          []
        )

      assert response.status == 204

      assert {"access-control-allow-origin", "https://www.doctolib.fr"} in response.resp_headers,
             "access-control-allow-origin response header"

      assert {"access-control-allow-headers", "authorization"} in response.resp_headers,
             "access-control-allow-headers response header"

      assert {"access-control-allow-methods", "GET"} in response.resp_headers,
             "access-control-allow-methods response header"

      assert {"access-control-max-age",
              Integer.to_string(Application.fetch_env!(:neurow, :public_api_preflight_max_age))} in response.resp_headers,
             "access-control-max-age response header"
    end
  end

  describe "context path" do
    setup do
      Application.put_env(:neurow, :public_api_context_path, "/context_path")
      on_exit(fn -> Application.put_env(:neurow, :public_api_context_path, "") end)
      :ok
    end

    test "the authentication logic is applyed to urls prefixed by the context path" do
      conn =
        conn(:get, "/v1/subscribe")

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 403}
        assert_receive {:chunk, body}

        sse_event = parse_sse_event(body)

        assert sse_event.event == "neurow_error_forbidden"
      end)
    end

    test "The subscribe url is prefixed with the context path" do
      conn =
        conn(:get, "/context_path/v1/subscribe")
        |> put_req_header(
          "authorization",
          "Bearer #{compute_jwt_token_in_req_header_public_api("test_topic1")}"
        )

      call(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}
        publish_message("test_issuer1-test_topic1", 1234, "A message")

        assert_receive {:chunk, first_event}

        assert parse_sse_event(first_event) == %{
                 id: "1234",
                 event: "test-event",
                 data: "A message"
               }
      end)
    end
  end

  defp publish_message(topic, id, message) do
    :ok =
      Neurow.Broker.ReceiverShardManager.broadcast(topic, %Neurow.Broker.Message{
        event: "test-event",
        payload: message,
        timestamp: id
      })
  end
end
