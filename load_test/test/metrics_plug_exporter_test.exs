defmodule MetricsPlugExporterTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  test "init/1 returns the opts unchanged" do
    assert MetricsPlugExporter.init(:some_opts) == :some_opts
  end

  test "serves the prometheus text format on /metrics and halts the pipeline" do
    response = MetricsPlugExporter.call(conn(:get, "/metrics"), [])

    assert response.halted
    assert response.status == 200
    assert get_resp_header(response, "content-type") == [:prometheus_text_format.content_type()]
    assert IO.iodata_to_binary(response.resp_body) =~ "# TYPE"
  end

  test "lets other paths pass through unchanged" do
    response = MetricsPlugExporter.call(conn(:get, "/ping"), [])

    refute response.halted
    refute response.status
    refute response.resp_body
  end
end
