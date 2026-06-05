defmodule Neurow.Observability.HttpInterfacesStatsTest do
  use ExUnit.Case
  use Prometheus.Metric

  alias Neurow.Observability.HttpInterfacesStats

  setup_all do
    Counter.declare(
      name: :http_request_exception_count,
      labels: [:interface, :kind],
      help: "HTTP request exception count"
    )

    Counter.declare(
      name: :http_request_early_error_count,
      labels: [:status],
      help: "HTTP request early_error count"
    )

    :ok
  end

  defp counter_value(name, labels) do
    case Counter.value(name: name, labels: labels) do
      :undefined -> 0
      n -> n
    end
  end

  describe "handle_event [:cowboy, :request, :exception]" do
    test "increments exception counter for public_api" do
      before = counter_value(:http_request_exception_count, [:public_api, "error"])

      HttpInterfacesStats.handle_event(
        [:cowboy, :request, :exception],
        %{},
        %{req: %{path: "/v1/subscribe", ref: Neurow.PublicApi.Endpoint.HTTP}, kind: :error},
        nil
      )

      assert counter_value(:http_request_exception_count, [:public_api, "error"]) == before + 1
    end

    test "increments exception counter for internal_api" do
      before = counter_value(:http_request_exception_count, [:internal_api, "throw"])

      HttpInterfacesStats.handle_event(
        [:cowboy, :request, :exception],
        %{},
        %{req: %{path: "/v1/messages", ref: Neurow.InternalApi.Endpoint.HTTP}, kind: :throw},
        nil
      )

      assert counter_value(:http_request_exception_count, [:internal_api, "throw"]) == before + 1
    end

    test "uses the kind as a string label" do
      before_exit = counter_value(:http_request_exception_count, [:public_api, "exit"])

      HttpInterfacesStats.handle_event(
        [:cowboy, :request, :exception],
        %{},
        %{req: %{path: "/v1/subscribe", ref: Neurow.PublicApi.Endpoint.HTTP}, kind: :exit},
        nil
      )

      assert counter_value(:http_request_exception_count, [:public_api, "exit"]) ==
               before_exit + 1
    end

    test "does not increment for unmonitored paths" do
      Enum.each(["/ping", "/favicon.ico", "/metrics"], fn path ->
        before = counter_value(:http_request_exception_count, [:public_api, "error"])

        HttpInterfacesStats.handle_event(
          [:cowboy, :request, :exception],
          %{},
          %{req: %{path: path, ref: Neurow.PublicApi.Endpoint.HTTP}, kind: :error},
          nil
        )

        assert counter_value(:http_request_exception_count, [:public_api, "error"]) == before
      end)
    end
  end

  describe "handle_event [:cowboy, :request, :early_error]" do
    test "increments early_error counter with binary status" do
      before = counter_value(:http_request_early_error_count, ["400"])

      HttpInterfacesStats.handle_event(
        [:cowboy, :request, :early_error],
        %{},
        %{req: %{path: "/v1/subscribe"}, resp_status: "400 Bad Request"},
        nil
      )

      assert counter_value(:http_request_early_error_count, ["400"]) == before + 1
    end

    test "increments early_error counter with integer status" do
      before = counter_value(:http_request_early_error_count, ["400"])

      HttpInterfacesStats.handle_event(
        [:cowboy, :request, :early_error],
        %{},
        %{req: %{path: "/v1/subscribe"}, resp_status: 400},
        nil
      )

      assert counter_value(:http_request_early_error_count, ["400"]) == before + 1
    end

    test "does not increment for unmonitored paths" do
      Enum.each(["/ping", "/favicon.ico", "/metrics"], fn path ->
        before = counter_value(:http_request_early_error_count, ["400"])

        HttpInterfacesStats.handle_event(
          [:cowboy, :request, :early_error],
          %{},
          %{req: %{path: path}, resp_status: "400 Bad Request"},
          nil
        )

        assert counter_value(:http_request_early_error_count, ["400"]) == before
      end)
    end
  end
end
