defmodule Neurow.Observability.HttpInterfacesStatsTest do
  use ExUnit.Case
  use Prometheus.Metric

  alias Neurow.Observability.HttpInterfacesStats

  setup_all do
    HttpInterfacesStats.setup()
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

      :telemetry.execute(
        [:cowboy, :request, :exception],
        %{},
        %{req: %{path: "/v1/subscribe", ref: Neurow.PublicApi.Endpoint.HTTP}, kind: :error}
      )

      assert counter_value(:http_request_exception_count, [:public_api, "error"]) == before + 1
    end

    test "increments exception counter for internal_api" do
      before = counter_value(:http_request_exception_count, [:internal_api, "throw"])

      :telemetry.execute(
        [:cowboy, :request, :exception],
        %{},
        %{req: %{path: "/v1/messages", ref: Neurow.InternalApi.Endpoint.HTTP}, kind: :throw}
      )

      assert counter_value(:http_request_exception_count, [:internal_api, "throw"]) == before + 1
    end

    test "uses the kind as a string label" do
      before_exit = counter_value(:http_request_exception_count, [:public_api, "exit"])

      :telemetry.execute(
        [:cowboy, :request, :exception],
        %{},
        %{req: %{path: "/v1/subscribe", ref: Neurow.PublicApi.Endpoint.HTTP}, kind: :exit}
      )

      assert counter_value(:http_request_exception_count, [:public_api, "exit"]) ==
               before_exit + 1
    end

    test "does not increment for unmonitored paths" do
      Enum.each(HttpInterfacesStats.unmonitored_request_paths(), fn path ->
        before = counter_value(:http_request_exception_count, [:public_api, "error"])

        :telemetry.execute(
          [:cowboy, :request, :exception],
          %{},
          %{req: %{path: path, ref: Neurow.PublicApi.Endpoint.HTTP}, kind: :error}
        )

        assert counter_value(:http_request_exception_count, [:public_api, "error"]) == before
      end)
    end
  end

  describe "handle_event [:cowboy, :request, :early_error]" do
    test "increments early_error counter for public_api with binary status" do
      before = counter_value(:http_request_early_error_count, [:public_api, "400"])

      :telemetry.execute(
        [:cowboy, :request, :early_error],
        %{},
        %{
          partial_req: %{path: "/v1/subscribe"},
          ref: Neurow.PublicApi.Endpoint.HTTP,
          resp_status: "400 Bad Request"
        }
      )

      assert counter_value(:http_request_early_error_count, [:public_api, "400"]) == before + 1
    end

    test "increments early_error counter for internal_api with integer status" do
      before = counter_value(:http_request_early_error_count, [:internal_api, "431"])

      :telemetry.execute(
        [:cowboy, :request, :early_error],
        %{},
        %{
          partial_req: %{path: "/v1/publish"},
          ref: Neurow.InternalApi.Endpoint.HTTP,
          resp_status: 431
        }
      )

      assert counter_value(:http_request_early_error_count, [:internal_api, "431"]) == before + 1
    end

    test "does not increment when partial_req is absent" do
      before_public = counter_value(:http_request_early_error_count, [:public_api, "400"])
      before_internal = counter_value(:http_request_early_error_count, [:internal_api, "400"])

      :telemetry.execute(
        [:cowboy, :request, :early_error],
        %{},
        %{ref: Neurow.PublicApi.Endpoint.HTTP, resp_status: "400 Bad Request"}
      )

      assert counter_value(:http_request_early_error_count, [:public_api, "400"]) == before_public
      assert counter_value(:http_request_early_error_count, [:internal_api, "400"]) == before_internal
    end

    test "does not increment when path is nil" do
      before = counter_value(:http_request_early_error_count, [:public_api, "400"])

      :telemetry.execute(
        [:cowboy, :request, :early_error],
        %{},
        %{
          partial_req: %{path: nil},
          ref: Neurow.PublicApi.Endpoint.HTTP,
          resp_status: "400 Bad Request"
        }
      )

      assert counter_value(:http_request_early_error_count, [:public_api, "400"]) == before
    end

    test "does not increment for unmonitored paths" do
      Enum.each(HttpInterfacesStats.unmonitored_request_paths(), fn path ->
        before = counter_value(:http_request_early_error_count, [:public_api, "400"])

        :telemetry.execute(
          [:cowboy, :request, :early_error],
          %{},
          %{
            partial_req: %{path: path},
            ref: Neurow.PublicApi.Endpoint.HTTP,
            resp_status: "400 Bad Request"
          }
        )

        assert counter_value(:http_request_early_error_count, [:public_api, "400"]) == before
      end)
    end
  end
end
