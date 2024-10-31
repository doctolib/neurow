defmodule Neurow.JwtAuthPlug do
  require Logger

  import Plug.Conn

  defmodule Options do
    defstruct [
      :credential_headers,
      :jwk_provider,
      :audience,
      :max_lifetime,
      :inc_error_callback,
      :send_forbidden,
      allowed_algorithm: "HS256",
      verbose_authentication_errors: false,
      exclude_path_prefixes: []
    ]

    def allowed_algorithm(options) do
      if is_function(options.allowed_algorithm),
        do: options.allowed_algorithm.(),
        else: options.allowed_algorithm
    end

    def audience(options) do
      if is_function(options.audience),
        do: options.audience.(),
        else: options.audience
    end

    def max_lifetime(options) do
      if is_function(options.max_lifetime),
        do: options.max_lifetime.(),
        else: options.max_lifetime
    end

    def verbose_authentication_errors?(options) do
      if is_function(options.verbose_authentication_errors),
        do: options.verbose_authentication_errors.(),
        else: options.verbose_authentication_errors
    end

    def jwk_provider(options, issuer_name), do: options.jwk_provider.(issuer_name)
  end

  def init(options), do: struct(Options, options)

  def call(conn, options) do
    case requires_jwt_authentication?(conn, options) do
      true ->
        with(
          {:ok, jwt_token_str} <- jwt_token_from_request(conn, options),
          {:ok, _protected, payload} <- parse_jwt_token(jwt_token_str),
          {:ok, jwks} <- fetch_jwks_from_issuer(payload, options),
          {:ok} <- check_signature(jwt_token_str, jwks, options),
          {:ok} <- check_expiration(payload, options),
          {:ok} <- check_audience(payload, options)
        ) do
          conn |> assign(:jwt_payload, payload.fields)
        else
          {:error, code, message} ->
            options.inc_error_callback.()
            conn |> forbidden(code, message, options)

          _ ->
            options.inc_error_callback.()
            conn |> forbidden(:authentication_error, "Authentication error", options)
        end

      false ->
        conn
    end
  end

  @doc """
  Utility method that generates jwt tokens for test purpose.
  # It is intended to be used in a iex session, or in a mix task.
  """
  def generate_jwt_token(
        issuer,
        jwk_provider,
        audience,
        sub \\ nil,
        lifetime \\ 60 * 2 - 1,
        algorithm \\ "HS256"
      ) do
    iat = :os.system_time(:second)
    exp = iat + lifetime

    jws = %{
      "alg" => algorithm
    }

    jwt =
      if is_binary(sub),
        do: %{
          "iss" => issuer,
          "exp" => exp,
          "iat" => iat,
          "aud" => audience,
          "sub" => sub
        },
        else: %{
          "iss" => issuer,
          "exp" => exp,
          "iat" => iat,
          "aud" => audience
        }

    case jwk_provider.(issuer) do
      [jwk] ->
        jwk_provider.(issuer)
        signed = JOSE.JWT.sign(jwk, jws, jwt)
        {%{alg: :jose_jws_alg_hmac}, compact_signed} = JOSE.JWS.compact(signed)
        compact_signed

      nil ->
        raise ArgumentError, message: "Unknown issuer '#{issuer}'"
    end
  end

  defp requires_jwt_authentication?(conn, options) do
    !Enum.any?(options.exclude_path_prefixes, fn excluded_path_prefix ->
      String.starts_with?(conn.request_path, excluded_path_prefix)
    end)
  end

  defp jwt_token_from_request(conn, options) do
    Enum.find_value(options.credential_headers, fn header ->
      case get_req_header(conn, header) do
        ["Bearer " <> jwt_token] -> jwt_token
        _ -> nil
      end
    end)
    |> case do
      nil -> {:error, :invalid_authorization_header, "Invalid authorization header"}
      jwt_token -> {:ok, jwt_token}
    end
  end

  defp parse_jwt_token(jwt_token_str) do
    try do
      protected = JOSE.JWT.peek_protected(jwt_token_str)
      payload = JOSE.JWT.peek_payload(jwt_token_str)
      {:ok, protected, payload}
    rescue
      _ -> {:error, :invalid_jwt_token, "Invalid JWT token"}
    end
  end

  defp fetch_jwks_from_issuer(payload, options) do
    case payload do
      %JOSE.JWT{fields: %{"iss" => issuer}} ->
        jwks = options |> Options.jwk_provider(issuer)

        if jwks != nil && !Enum.empty?(jwks) do
          {:ok, jwks}
        else
          {:error, :unknown_issuer, "Unknown issuer"}
        end

      _ ->
        {:error, :missing_iss_claim, "Missing iss claim"}
    end
  end

  defp check_signature(jwt_token_str, jwks, options) do
    valid_jwk =
      Enum.find_value(jwks, false, fn jwk ->
        case JOSE.JWT.verify_strict(jwk, [options |> Options.allowed_algorithm()], jwt_token_str) do
          {true, _jwt, _jws} -> true
          {false, _jwt, _jws} -> false
          _ -> false
        end
      end)

    case valid_jwk do
      true -> {:ok}
      false -> {:error, :invalid_signature, "Invalid signature"}
    end
  end

  defp check_expiration(payload, options) do
    case payload do
      %JOSE.JWT{fields: %{"exp" => exp, "iat" => iat}}
      when is_integer(exp) and is_integer(iat) and exp > iat ->
        if exp - iat > options |> Options.max_lifetime() do
          {:error, :too_long_lifetime, "Token lifetime is higher than allowed"}
        else
          if exp > :os.system_time(:second) do
            {:ok}
          else
            {:error, :token_expired, "Token expired"}
          end
        end

      _ ->
        {:error, :invalid_exp_iat_claim, "Invalid exp or iat claim"}
    end
  end

  defp check_audience(payload, options) do
    case payload do
      %JOSE.JWT{fields: %{"aud" => audience}} ->
        if audience == options |> Options.audience() do
          {:ok}
        else
          {:error, :unknwon_audience, "Unkown audience"}
        end

      _ ->
        {:error, :missing_aud_claim, "Missing aud claim"}
    end
  end

  defp forbidden(conn, error_code, error_message, options) do
    jwt_token =
      case conn |> jwt_token_from_request(options) do
        {:ok, jwt_token} -> jwt_token
        _ -> nil
      end

    Logger.error(
      "JWT authentication error: #{error_code} - #{error_message}, path: '#{conn.request_path}', audience: '#{options |> Options.audience()}', token: '#{jwt_token}'",
      category: "security",
      error_code: "jwt_authentication.#{error_code}",
      trace_id: conn |> get_req_header("x-request-id") |> List.first(),
      client_ip: conn |> get_req_header("x-forwarded-for") |> List.first()
    )

    conn =
      if options |> Options.verbose_authentication_errors?(),
        do: conn |> options.send_forbidden.(error_code, error_message),
        else:
          conn
          |> options.send_forbidden.(
            :invalid_authentication_token,
            "Invalid authentication token"
          )

    conn |> halt
  end
end
