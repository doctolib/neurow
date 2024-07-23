defmodule Neurow.InternalApi do
  require Logger
  require Node
  import Plug.Conn
  alias Neurow.InternalApi.PublishRequest

  use Plug.Router
  plug(MetricsPlugExporter)

  plug(Neurow.JwtAuthPlug,
    jwk_provider: &Neurow.Configuration.internal_api_issuer_jwks/1,
    audience: &Neurow.Configuration.internal_api_audience/0,
    verbose_authentication_errors:
      &Neurow.Configuration.internal_api_verbose_authentication_errors/0,
    max_lifetime: &Neurow.Configuration.internal_api_jwt_max_lifetime/0,
    count_error: &Stats.inc_jwt_errors_internal/0,
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
      {:ok, messages, topics} ->
        message_id = to_string(:os.system_time(:millisecond))

        nb_publish = length(messages) * length(topics)

        Enum.each(topics, fn topic ->
          Enum.each(messages, fn message ->
            Phoenix.PubSub.broadcast!(
              Neurow.PubSub,
              topic,
              {:pubsub_message, message_id, message}
            )

            Stats.inc_msg_received()
            Logger.debug("Message published on topic: #{topic}")
          end)
        end)

        conn
        |> put_resp_header("content-type", "text/plain")
        |> send_resp(200, "#{nb_publish} messages published\n")

      {:error, reason} ->
        conn |> resp(:bad_request, reason)
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp extract_params(conn) do
    with(
      {:ok, issuer} <- issuer(conn),
      publish_request <- PublishRequest.from_json(conn.body_params),
      :ok <- PublishRequest.validate(publish_request)
    ) do
      full_topics =
        Enum.map(PublishRequest.topics(publish_request), fn topic -> "#{issuer}-#{topic}" end)

      {:ok, PublishRequest.messages(publish_request), full_topics}
    else
      error ->
        error
    end
  end

  defp issuer(conn) do
    case conn.assigns[:jwt_payload]["iss"] do
      nil -> {:error, "JWT iss is nil"}
      "" -> {:error, "JWT iss is empty"}
      issuer -> {:ok, issuer}
    end
  end
end
