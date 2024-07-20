defmodule Mix.Tasks.GenerateJwtToken do
  @moduledoc """
  This mix task generates JWT tokens that are accepted by the public and internal APIs, by using
  authentication settings defined in the neurow configuration.
  """

  @doc """
  ## Examples

  Generate tokens for the public API:
  ```
  mix generate_jwt_token --api=public --issuer=test_issuer1 --topic=user:1234
  ```

  Generate tokens for the internal API:
  ```
  mix generate_jwt_token --api=internal --issuer=test_issuer1
  ```

  """

  use Mix.Task

  @requirements ["app.config"]

  def run(args) do
    {parsed_args, _args, _invalid} =
      OptionParser.parse(args, strict: [api: :string, issuer: :string, topic: :string])

    Neurow.Configuration.start_link(%{})

    case {parsed_args[:api], parsed_args[:issuer], parsed_args[:topic]} do
      {"public", issuer, topic} when is_binary(issuer) and is_binary(topic) ->
        IO.puts(
          Neurow.JwtAuthPlug.generate_jwt_token(
            issuer,
            &Neurow.Configuration.public_api_issuer_jwks/1,
            Neurow.Configuration.public_api_audience(),
            topic
          )
        )

      {"public", issuer, _topic} when is_nil(issuer) ->
        raise ArgumentError, message: "An issuer is expected"

      {"public", _issuer, topic} when is_nil(topic) ->
        raise ArgumentError, message: "A topic is expected"

      {"internal", issuer, _topic} when is_binary(issuer) ->
        IO.puts(
          Neurow.JwtAuthPlug.generate_jwt_token(
            issuer,
            &Neurow.Configuration.internal_api_issuer_jwks/1,
            Neurow.Configuration.internal_api_audience()
          )
        )

      {"internal", issuer, _topic} when is_nil(issuer) ->
        raise ArgumentError, message: "An issuer is expected"

      {_other_api, _issuer, _topic} ->
        raise ArgumentError,
          message: "Invalid api '#{parsed_args[:api]}', expecting 'public' or 'internal'"
    end
  end
end
