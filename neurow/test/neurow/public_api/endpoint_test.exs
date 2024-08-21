defmodule Neurow.PublicApi.EndpointTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper
  import SseHelper

  describe "authentication" do
    test "denies access if no JWT token is provided" do
      conn =
        conn(:get, "/v1/subscribe")

      call_sse(Neurow.PublicApi.Endpoint, conn, fn ->
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

      call_sse(Neurow.PublicApi.Endpoint, conn, fn ->
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

      call_sse(Neurow.PublicApi.Endpoint, conn, fn ->
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

      call_sse(Neurow.PublicApi.Endpoint, conn, fn ->
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

    test "transmits message history on subscription if the Last-Event-Id is sent" do
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

      publish_message("test_issuer1-test_topic1", 1, "Message ID1")
      publish_message("test_issuer1-test_topic1", 5, "Message ID5")
      publish_message("test_issuer1-test_topic1", 6, "Message ID6")
      publish_message("test_issuer1-other_topic", 7, "This message is not expected")
      publish_message("test_issuer1-test_topic1", 8, "Message ID8")

      call_sse(Neurow.PublicApi.Endpoint, conn, fn ->
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

    test "returns a bad request error if the Last-Event_Id header is invalid" do
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

      call_sse(Neurow.PublicApi.Endpoint, conn, fn ->
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

      call_sse(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}
        assert_receive {:DOWN, _reference, :process, _pid, :normal}, 20_000
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

      call_sse(Neurow.PublicApi.Endpoint, conn, fn ->
        assert_receive {:send_chunked, 200}
        assert_receive {:chunk, body}, 20_000
        event = parse_sse_event(body)

        assert event.event == "ping"
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

  defp publish_message(topic, id, message) do
    :ok =
      Neurow.ReceiverShardManager.broadcast(topic, %Neurow.InternalApi.Message{
        event: "test-event",
        payload: message,
        timestamp: id
      })
  end
end
