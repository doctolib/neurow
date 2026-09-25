defmodule HttpTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  test "GET /metrics serves the Prometheus text format" do
    response = Http.call(conn(:get, "/metrics"), [])

    assert response.status == 200
    assert get_resp_header(response, "content-type") == [:prometheus_text_format.content_type()]
    assert IO.iodata_to_binary(response.resp_body) =~ "# TYPE"
  end

  test "other paths return 404" do
    response = Http.call(conn(:get, "/foo"), [])

    assert response.status == 404
  end
end
