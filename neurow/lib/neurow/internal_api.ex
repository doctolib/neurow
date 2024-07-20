defmodule Neurow.InternalApi do
  require Logger
  require Node
  import Plug.Conn
  use Plug.Router
  plug(MetricsPlugExporter)

  plug(Neurow.JwtAuthPlug,
    jwk_provider: &Neurow.Configuration.internal_api_issuer_jwks/1,
    audience: &Neurow.Configuration.internal_api_audience/0,
    verbose_authentication_errors:
      &Neurow.Configuration.internal_api_verbose_authentication_errors/0,
    exclude_path_prefixes: ["/ping", "/nodes", "/cluster_size_above"]
  )

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  get "/" do
    conn
    |> put_resp_header("content-type", "text/plain")
    |> send_resp(200, "ok")
  end

  get "/ping" do
    conn
    |> put_resp_header("content-type", "text/plain")
    |> send_resp(200, "ok")
  end

  get "/nodes" do
    nodes = Node.list()

    conn
    |> put_resp_header("content-type", "text/plain")
    |> send_resp(
      200,
      "Current node: #{node()}\r\nTotal nodes: #{length(nodes) + 1}\r\nNodes: #{inspect(nodes)}\r\n"
    )
  end

  get "/cluster_size_above/:size" do
    size = String.to_integer(size)
    cluster_size = length(Node.list()) + 1

    conn
    |> put_resp_header("content-type", "text/plain")
    |> send_resp((cluster_size >= size && 200) || 404, "Cluster size: #{cluster_size}\n")
  end

  post "/v1/publish" do
    case extract_params(conn) do
      {:ok, message, topic} ->
        message_id = to_string(:os.system_time(:millisecond))

        :ok =
          Phoenix.PubSub.broadcast!(Neurow.PubSub, topic, {:pubsub_message, message_id, message})

        Logger.debug("Message published on topic: #{topic}")
        Stats.inc_msg_received()

        conn
        |> put_resp_header("content-type", "text/html")
        |> send_resp(200, "Published #{message} to #{topic}\n")

      {:error, reason} ->
        conn |> resp(:bad_request, reason)
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp extract_params(conn) do
    with(
      {:ok, issuer} <- extract_issuer(conn),
      {:ok, message} <- extract_param(conn, "message"),
      {:ok, topic} <- extract_param(conn, "topic")
    ) do
      full_topic = "#{issuer}-#{topic}"
      {:ok, message, full_topic}
    else
      error -> error
    end
  end

  defp extract_issuer(conn) do
    case conn.assigns[:jwt_payload]["iss"] do
      nil -> {:error, "JWT iss is nil"}
      "" -> {:error, "JWT iss is empty"}
      issuer -> {:ok, issuer}
    end
  end

  defp extract_param(conn, key) do
    case conn.body_params[key] do
      nil -> {:error, "#{key} is nil"}
      "" -> {:error, "#{key} is empty"}
      output -> {:ok, output}
    end
  end
end