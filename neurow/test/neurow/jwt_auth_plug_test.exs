defmodule Neurow.JwtAuthPlugTest do
  use ExUnit.Case
  use Plug.Test
  import JwtHelper

  # Can be generated with `JOSE.JWS.generate_key(%{"alg" => "HS256"}) |> JOSE.JWK.to_map |> elem(1)`
  @issuer_1_jwk_1 JOSE.JWK.from_oct("r0daWG1tSxMTSzD4MuxwMe46h19_cEhMmrn5mKLncKk")
  @issuer_1_jwk_2 JOSE.JWK.from_oct("P5BmrxCjG4dldXnesWz5djxTMOvCPBHj71OFs2vfs6k")

  @issuer_2_jwk JOSE.JWK.from_oct("74vtYMCB5ihcf8EvvIEgNVxMeT6XshTAp1TEOqzNa90")

  @test_audience "test_audience"

  setup_all do
    {:ok,
     default_opts:
       Neurow.JwtAuthPlug.init(%{
         credential_headers: ["authorization"],
         audience: @test_audience,
         verbose_authentication_errors: true,
         max_lifetime: 60 * 2,
         # For testing that the call to send_forbidden is properly delegated, error codes and messages
         # are just stored in conn to be asserted after
         send_forbidden: fn conn, error_code, error_message ->
           conn |> assign(:forbidden_error, {error_code, error_message})
         end,
         send_unauthorized: fn conn, error_code, error_message ->
           conn |> assign(:unauthorized_error, {error_code, error_message})
         end,
         jwk_provider: fn issuer ->
           case issuer do
             "issuer_1" -> [@issuer_1_jwk_1, @issuer_1_jwk_2]
             "issuer_2" -> [@issuer_2_jwk]
             _ -> nil
           end
         end,
         inc_error_callback: fn -> :ok end,
         exclude_path_prefixes: ["/excluded_path"]
       })}
  end

  test "forwards the request to the plug pipeline if a valid JWT token is provided in the request",
       %{
         default_opts: opts
       } do
    jwt_payload = valid_issuer_1_jwt_payload()

    response =
      Neurow.JwtAuthPlug.call(
        conn(:get, "/test")
        |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
        opts
      )

    refute response.halted
    refute response.status
    refute response.resp_body
    assert response.assigns[:jwt_payload] == jwt_payload
  end

  test "checks authentication and forward the request to the plug pipeline if the request path matches a excluded path",
       %{
         default_opts: opts
       } do
    response =
      Neurow.JwtAuthPlug.call(
        conn(:get, "/excluded_path"),
        opts
      )

    refute response.halted
    refute response.status
    refute response.resp_body
    assert response.assigns[:jwt_payload] == nil

    response =
      Neurow.JwtAuthPlug.call(
        conn(:get, "/excluded_path/subresource"),
        opts
      )

    refute response.halted
    refute response.status
    refute response.resp_body
    assert response.assigns[:jwt_payload] == nil
  end

  test "do not provide details about authentication errors if verbose_authentication_errors is set to false",
       %{
         default_opts: opts
       } do
    response =
      Neurow.JwtAuthPlug.call(
        conn(:get, "/test") |> put_req_header("authorization", "Basic dXNlcjpwYXNzd29yZA=="),
        %Neurow.JwtAuthPlug.Options{opts | verbose_authentication_errors: false}
      )

    assert response.halted

    assert response.assigns[:unauthorized_error] ==
             {:invalid_authorization_header, "Invalid authorization header"},
           "Error details"
  end

  describe "Authorization header" do
    test "denies access if the authorization header is not provided", %{default_opts: opts} do
      response = Neurow.JwtAuthPlug.call(conn(:get, "/test"), opts)

      assert response.halted, "Response halted"
      assert response.halted

      assert response.assigns[:unauthorized_error] ==
               {:invalid_authorization_header, "Invalid authorization header"},
             "Error details"
    end

    test "denies access if the authorization header does not contain a bearer token", %{
      default_opts: opts
    } do
      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_req_header("authorization", "Basic dXNlcjpwYXNzd29yZA=="),
          opts
        )

      assert response.halted

      assert response.assigns[:unauthorized_error] ==
               {:invalid_authorization_header, "Invalid authorization header"},
             "Error details"
    end

    test "denies access if the bearer token is not a well formed JWT token", %{
      default_opts: opts
    } do
      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test") |> put_req_header("authorization", "Bearer not_a_jwt_token"),
          opts
        )

      assert response.halted

      assert response.assigns[:unauthorized_error] ==
               {:invalid_jwt_token, "Invalid JWT token"},
             "Error details"
    end
  end

  describe "issuer" do
    test "denies access if the JWT token does not contain any issuer", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.delete("iss")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:missing_iss_claim, "Missing iss claim"},
             "Error details"
    end

    test "denies access if the iss claim does not match any registered issuer", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.put("iss", "issuer_3")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:unknown_issuer, "Unknown issuer"},
             "Error details"
    end
  end

  describe "JWT signature" do
    test "allows access if the jwt token is signed by a secondary signature attached to the issuer",
         %{
           default_opts: opts
         } do
      jwt_payload = valid_issuer_1_jwt_payload()

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_2),
          opts
        )

      refute response.halted
      refute response.status
      refute response.resp_body
      assert response.assigns[:jwt_payload] == jwt_payload
    end

    test "denies access if the signature is not provided in the token", %{
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

      assert response.assigns[:unauthorized_error] ==
               {:invalid_jwt_token, "Invalid JWT token"},
             "Error details"
    end

    test "denies access if the signature is invalid", %{
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

      assert response.assigns[:forbidden_error] ==
               {:invalid_signature, "Invalid signature"},
             "Error details"
    end

    test "denies access if the token is signed with another secret", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload()

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_2_jwk),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:invalid_signature, "Invalid signature"},
             "Error details"
    end
  end

  describe "token expiration" do
    test "denies access if no iat claim is provided", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.delete("iat")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:invalid_exp_iat_claim, "Invalid exp or iat claim"},
             "Error details"
    end

    test "denies access if the iat claim is not a number", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.put("iat", "not_a_number")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:invalid_exp_iat_claim, "Invalid exp or iat claim"},
             "Error details"
    end

    test "denies access if no exp claim is provided", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.delete("exp")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:invalid_exp_iat_claim, "Invalid exp or iat claim"},
             "Error details"
    end

    test "denies access if the exp claim is not a number", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.put("exp", "not_a_number")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:invalid_exp_iat_claim, "Invalid exp or iat claim"},
             "Error details"
    end

    test "denies access if the exp claim is not after the iat claim", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload()
      jwt_payload = jwt_payload |> Map.put("exp", jwt_payload["iat"] - 10)

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:invalid_exp_iat_claim, "Invalid exp or iat claim"},
             "Error details"
    end

    test "denies access if the token expired", %{
      default_opts: opts
    } do
      jwt_payload =
        valid_issuer_1_jwt_payload()
        |> Map.put("iat", :os.system_time(:second) - 10)
        |> Map.put("exp", :os.system_time(:second) - 1)

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:token_expired, "Token expired"},
             "Error details"
    end

    test "denies access if the token lifetime is higher than expected", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload()

      jwt_payload =
        jwt_payload
        |> Map.put("iat", :os.system_time(:second) - 10)
        |> Map.put("exp", jwt_payload["iat"] + opts.max_lifetime + 1)

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:too_long_lifetime, "Token lifetime is higher than allowed"},
             "Error details"
    end
  end

  describe "token audience" do
    test "denies access if the aud claim is not provided", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.delete("aud")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:missing_aud_claim, "Missing aud claim"},
             "Error details"
    end

    test "denies access if the aud claim does not match the expected audience", %{
      default_opts: opts
    } do
      jwt_payload = valid_issuer_1_jwt_payload() |> Map.put("aud", "invalid_audience")

      response =
        Neurow.JwtAuthPlug.call(
          conn(:get, "/test")
          |> put_jwt_token_in_req_header(jwt_payload, @issuer_1_jwk_1),
          opts
        )

      assert response.halted

      assert response.assigns[:forbidden_error] ==
               {:unknwon_audience, "Unkown audience"},
             "Error details"
    end
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
end
