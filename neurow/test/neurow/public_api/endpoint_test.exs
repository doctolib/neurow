defmodule Neurow.PublicApi.EndpointTest do
  use ExUnit.Case
  use Plug.Test

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
end
