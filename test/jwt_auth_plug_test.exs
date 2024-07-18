defmodule Neurow.JwtAuthPlugTest do
  alias Neurow.JwtAuthPlug
  use ExUnit.Case
  use Plug.Test

  # Can be generated with `JOSE.JWS.generate_key(%{"alg" => "HS256"}) |> JOSE.JWK.to_map |> elem(1)`
  @issuer_1_jwk_1 JOSE.JWK.from_oct("r0daWG1tSxMTSzD4MuxwMe46h19_cEhMmrn5mKLncKk")
  @issuer_1_jwk_2 JOSE.JWK.from_oct("P5BmrxCjG4dldXnesWz5djxTMOvCPBHj71OFs2vfs6k")

  @issuer_2_jwk JOSE.JWK.from_oct("74vtYMCB5ihcf8EvvIEgNVxMeT6XshTAp1TEOqzNa90")

  @test_audience "test_audience"

  setup_all do
    {:ok,
     default_opts:
       Neurow.JwtAuthPlug.init(%{
         audience: @test_audience,
         verbose_authentication_errors: true,
         jwk_provider: fn issuer ->
           case issuer do
             "issuer_1" -> [@issuer_1_jwk_1, @issuer_1_jwk_2]
             "issuer_2" -> [@issuer_2_jwk]
             _ -> nil
           end
         end
       })}
  end

  test "should forward the request to the plug pipeline if a valid JWT token is provided in the request",
       %{
         default_opts: opts
       } do
    jwt_payload = valid_issuer_1_jwt_payload()

    response =
      Neurow.JwtAuthPlug.call(
        conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
        opts
      )

    refute response.halted
    refute response.status
    refute response.resp_body
    assert response.assigns[:jwt_payload] == jwt_payload
  end


  test "does not provide details about authentication errors if verbose_authentication_errors is set to false",
  %{
    default_opts: opts
  } do
    response =
      Neurow.JwtAuthPlug.call(
        conn(:get, "/test") |> put_req_header("authorization", "Basic dXNlcjpwYXNzd29yZA=="),
        %JwtAuthPlug.Options{ opts | verbose_authentication_errors: false}
      )

    assert response.halted
    assert 403 == response.status, "HTTP status"

    assert {"content-type", "application/json"} in response.resp_headers,
           "Response content type"

    assert error_code(response) == "invalid_authentication_token", "Response body error code"
  end


  describe "Authorization header" do
    test "should deny access if the authorization header is not provided", %{default_opts: opts} do
      response = Neurow.JwtAuthPlug.call(conn(:get, "/test"), opts)

      assert response.halted, "Response halted"
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_authorization_header", "Response body error code"
    end

    test "should deny access if the authorization header does not contain a bearer token", %{
      default_opts: opts
    } do
      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_req_header("authorization", "Basic dXNlcjpwYXNzd29yZA=="),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_authorization_header", "Response body error code"
    end

    test "should deny access if the bearer token is not a well formed JWT token", %{
      default_opts: opts
    } do
      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_req_header("authorization", "Bearer not_a_jwt_token"),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_jwt_token", "Response body error code"
    end
  end

  describe "issuer" do
    test "should deny access if the JWT token does not contain any issuer", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.delete("iss")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "missing_iss_claim", "Response body error code"
    end

    test "should deny access if the iss claim does not match any registered issuer", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.put("iss", "issuer_3")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "unkown_issuer", "Response body error code"
    end
  end

  describe "JWT signature" do
    test "should allow access if the jwt token is signed by a secondary signature attached to the issuer",
         %{
           default_opts: opts
         } do
      jwt_payload = valid_issuer_1_jwt_payload()

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_2),
          opts
        )

      refute response.halted
      refute response.status
      refute response.resp_body
      assert response.assigns[:jwt_payload] == jwt_payload
    end

    test "should deny access if the signature is not provided in the token", %{
      default_opts: opts
    } do
      [header, payload, _signature] =
        signed_jwt_token(valid_issuer_1_jwt_payload(), @issuer_1_jwk_1) |> String.split(".")

      invalid_jwt_token = header <> "." <> payload

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_req_header("authorization", "Bearer #{invalid_jwt_token}"),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_jwt_token", "Response body error code"
    end

    test "should deny access if the signature is invalid", %{
      default_opts: opts
    } do
      [header, payload, _signature] =
        signed_jwt_token(valid_issuer_1_jwt_payload(), @issuer_1_jwk_1) |> String.split(".")

      invalid_jwt_token = header <> "." <> payload <> ".invalid_signature"

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_req_header("authorization", "Bearer #{invalid_jwt_token}"),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_signature", "Response body error code"
    end

    test "should deny access if the token is signed with another secret", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload()

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_2_jwk),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_signature", "Response body error code"
    end
  end

  describe "token expiration" do
    test "should deny access if no iat claim is provided", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.delete("iat")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_exp_iat_claim", "Response body error code"
    end

    test "should deny access if the iat claim is not a number", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.put("iat", "not_a_number")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_exp_iat_claim", "Response body error code"
    end

    test "should deny access if no exp claim is provided", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.delete("exp")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_exp_iat_claim", "Response body error code"
    end

    test "should deny access if the exp claim is not a number", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.put("exp", "not_a_number")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_exp_iat_claim", "Response body error code"
    end

    test "should deny access if the exp claim is not after the iat claim", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload()
      jwt_payload = jwt_payload |> Map.put("exp", jwt_payload["iat"] - 10)

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "invalid_exp_iat_claim", "Response body error code"
    end

    test "should deny access if the token expired", %{
      default_opts: opts
    } do
      jwt_payload =
        valid_issuer_1_jwt_payload()
        |> Map.put("iat", :os.system_time(:second) - 10)
        |> Map.put("exp", :os.system_time(:second) - 1)

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "token_expired", "Response body error code"
    end

    test "should deny access if the token lifetime is higher than expected", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload()

      jwt_payload =
        jwt_payload
        |> Map.put("iat", :os.system_time(:second) - 10)
        |> Map.put("exp", jwt_payload["iat"] + opts.max_lifetime + 1)

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "too_long_lifetime", "Response body error code"
    end
  end

  describe "token audience" do
    test "should deny access if the aud claim is not provided", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.delete("aud")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "missing_aud_claim", "Response body error code"
    end

    test "should deny access if the aud claim does not match the expected audience", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.put("aud", "invalid_audience")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted
      assert 403 == response.status, "HTTP status"

      assert {"content-type", "application/json"} in response.resp_headers,
             "Response content type"

      assert error_code(response) == "unknwon_audience", "Response body error code"
    end
  end

  defp error_code(response) do
    {:ok, json_body} = Jason.decode(response.resp_body)
    json_body["errors"] |> Enum.at(0) |> Map.get("error_code")
  end

  defp valid_issuer_1_jwt_payload() do
    iat = :os.system_time(:second)
    exp = iat + (2 * 60 - 1)

    %{
      "iss" => "issuer_1",
      "exp" => exp,
      "iat" => iat,
      "aud" => @test_audience,
      "sub" => "record:123"
    }
  end

  defp signed_jwt_token(jwt, jwk) do
    jws = %{
      "alg" => "HS256"
    }

    signed = JOSE.JWT.sign(jwk, jws, jwt)
    {%{alg: :jose_jws_alg_hmac}, compact_signed} = JOSE.JWS.compact(signed)
    compact_signed
  end

  defp put_jwt_token_in_req_header(conn, jwt, jwk) do
    jwt_token = signed_jwt_token(jwt, jwk)
    conn |> put_req_header("authorization", "Bearer #{jwt_token}")
  end
end
