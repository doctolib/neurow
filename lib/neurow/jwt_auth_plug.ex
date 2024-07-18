defmodule Neurow.JwtAuthPlug do
  require Logger

  import Plug.Conn

  def init(options), do: options

  def call(conn, options) do
    case jwt_token_from_request(conn) do
      {:ok, jwt_token_str} ->
        case parse_jwt_token(jwt_token_str) do
          {:ok, _protected, payload} ->
            case fetch_jwks_from_issuer(payload, options) do
              {:ok, jwks} ->
                case check_signature(jwt_token_str, jwks, options) do
                  {:ok} ->
                    case check_expiration(payload, options) do
                      {:ok} ->
                        case check_audience(payload, options) do
                          {:ok} -> conn |> assign(:jwt_payload, payload.fields)
                          {:error, code, message} -> conn |> forbidden(code, message)
                        end

                      {:error, code, message} ->
                        conn |> forbidden(code, message)
                    end

                  {:error, code, message} ->
                    conn |> forbidden(code, message)
                end

              {:error, code, message} ->
                conn |> forbidden(code, message)
            end

          {:error, code, message} ->
            conn |> forbidden(code, message)
        end

      {:error, code, message} ->
        conn |> forbidden(code, message)
    end
  end

  defp jwt_token_from_request(conn) do
    case conn |> get_req_header("authorization") do
      ["Bearer " <> jwt_token] ->
        {:ok, jwt_token}

      _ ->
        {:error, :invalid_authorization_header, "Invalid authorization header"}
    end
  end

  defp parse_jwt_token(jwt_token_str) do
    try do
      protected = JOSE.JWT.peek_protected(jwt_token_str)
      payload = JOSE.JWT.peek_payload(jwt_token_str)
      {:ok, protected, payload}
    rescue
      _ in Jason.DecodeError -> {:error, :invalid_jwt_token, "Invalid JWT token"}
      _ in ArgumentError -> {:error, :invalid_jwt_token, "Invalid JWT token"}
    end
  end

  defp fetch_jwks_from_issuer(payload, options) do
    case payload do
      %JOSE.JWT{fields: %{"iss" => issuer}} ->
        jwks = options[:jwk_provider].(issuer)

        if jwks != nil && !Enum.empty?(jwks) do
          {:ok, jwks}
        else
          {:error, :unkown_issuer, "Unknown issuer"}
        end

      _ ->
        {:error, :missing_iss_claim, "Mising iss claim"}
    end
  end

  defp check_signature(jwt_token_str, jwks, options) do
    valid_jwk =
      Enum.find_value(jwks, false, fn jwk ->
        case JOSE.JWT.verify_strict(jwk, [options[:allowed_algorithm]], jwt_token_str) do
          {true, _jwt, _jws} -> true
          {false, _jwt, _jws} -> false
          _ -> false
        end
      end)

    case valid_jwk do
      true -> {:ok}
      false -> {:error, :invalid_signature, "Signature error"}
    end
  end

  defp check_expiration(payload, options) do
    case payload do
      %JOSE.JWT{fields: %{"exp" => exp, "iat" => iat}}
      when is_integer(exp) and is_integer(iat) and exp > iat ->
        if exp - iat > options[:max_lifetime] do
          {:error, :too_long_lifetime, "Token lifetime is higher than expected"}
        else
          if exp > :os.system_time(:second) do
            {:ok}
          else
            {:error, :token_expired, "Token expired"}
          end
        end

      _ ->
        {:error, :invalid_exp_iat_claim, "Bad exp or iat claim"}
    end
  end

  defp check_audience(payload, options) do
    case payload do
      %JOSE.JWT{fields: %{"aud" => audience}} ->
        if audience == options[:audience] do
          {:ok}
        else
          {:error, :unknwon_audience, "Unkown audience"}
        end

      _ ->
        {:error, :missing_aud_claim, "Missing aud claim"}
    end
  end

  defp forbidden(conn, error_code, error_message) do
    {:ok, response} =
      Jason.encode(%{
        errors: [
          %{error_code: error_code, error_message: error_message}
        ]
      })

    conn
    |> put_resp_header("content-type", "application/json")
    |> resp(:forbidden, response)
    |> halt
  end
end
