defmodule Neurow.InternalApi.Endpoint do
  require Logger
  require Node
  import Plug.Conn
  alias Neurow.InternalApi.PublishRequest
  alias Neurow.InternalApi.Message

  use Plug.Router
  plug(MetricsPlugExporter)

  plug(Neurow.JwtAuthPlug,
    jwk_provider: &Neurow.Configuration.internal_api_issuer_jwks/1,
    audience: &Neurow.Configuration.internal_api_audience/0,
    verbose_authentication_errors:
      &Neurow.Configuration.internal_api_verbose_authentication_errors/0,
    max_lifetime: &Neurow.Configuration.internal_api_jwt_max_lifetime/0,
    send_forbidden: &Neurow.InternalApi.Endpoint.send_forbidden/3,
    inc_error_callback: &Stats.inc_jwt_errors_internal/0,
    exclude_path_prefixes: ["/ping", "/nodes", "/cluster_size_above", "/history"]
  )

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: {:jiffy, :decode, [[:return_maps]]}
  )

  plug(:dispatch)

  # Resolved at compile time
  @revision System.get_env("GIT_COMMIT_SHA1")

  get "/" do
    conn
    |> put_resp_header("content-type", "text/plain")
    |> send_resp(200, "ok")
  end

  get "/ping" do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, Jason.encode!(%{status: :ok, revision: @revision}))
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

  get "/history/:topic" do
    history = Neurow.Broker.ReceiverShardManager.get_history(topic)

    history =
      Enum.map(history, fn {_, message} ->
        Map.from_struct(message)
      end)

    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, :jiffy.encode(history))
  end

  post "/v1/publish" do
    case extract_params(conn) do
      {:ok, messages, topics} ->
        publish_timestamp = :os.system_time(:millisecond)

        nb_publish =
          length(messages) * length(topics)

        Enum.each(topics, fn topic ->
          Enum.each(messages, fn message ->
            :ok =
              Neurow.Broker.ReceiverShardManager.broadcast(topic, %Message{
                message
                | timestamp: message.timestamp || publish_timestamp
              })

            Logger.debug("Message published on topic: #{topic}")
          end)
        end)

        Stats.inc_msg_received()

        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(
          200,
          :jiffy.encode(%{
            nb_published: nb_publish,
            publish_timestamp: publish_timestamp
          })
        )

      {:error, reason} ->
        conn |> send_error(:invalid_payload, reason)
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

  def send_forbidden(conn, error_code, error_message) do
    send_error(conn, error_code, error_message, :forbidden)
  end

  defp send_error(conn, error_code, error_message, status \\ :bad_request) do
    response =
      :jiffy.encode(%{
        errors: [
          %{error_code: error_code, error_message: error_message}
        ]
      })

    conn
    |> put_resp_header("content-type", "application/json")
    |> resp(status, response)
  end
end
