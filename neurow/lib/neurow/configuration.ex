defmodule Neurow.Configuration do
  use GenServer

  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  def public_api_issuer_jwks(issuer_name) do
    GenServer.call(__MODULE__, {:public_api_issuer_jwks, issuer_name})
  end

  def public_api_audience do
    Application.fetch_env!(:neurow, :public_api_authentication)[:audience]
  end

  def public_api_verbose_authentication_errors do
    Application.fetch_env!(:neurow, :public_api_authentication)[:verbose_authentication_errors]
  end

  def internal_api_issuer_jwks(issuer_name) do
    GenServer.call(__MODULE__, {:internal_api_issuer_jwks, issuer_name})
  end

  def internal_api_audience do
    Application.fetch_env!(:neurow, :internal_api_authentication)[:audience]
  end

  def internal_api_verbose_authentication_errors do
    Application.fetch_env!(:neurow, :internal_api_authentication)[
      :verbose_authentication_errors
    ]
  end

  def internal_api_jwt_max_lifetime do
    Application.fetch_env!(:neurow, :internal_api_jwt_max_lifetime)
  end

  def public_api_jwt_max_lifetime do
    Application.fetch_env!(:neurow, :public_api_jwt_max_lifetime)
  end

  def sse_timeout do
    Application.fetch_env!(:neurow, :sse_timeout)
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       public_api: %{
         issuer_jwks: build_issuer_jwks(:public_api_authentication)
       },
       internal_api: %{
         issuer_jwks: build_issuer_jwks(:internal_api_authentication)
       }
     }}
  end

  @impl true
  def handle_call({:public_api_issuer_jwks, issuer_name}, _from, state) do
    {:reply, state[:public_api][:issuer_jwks][issuer_name], state}
  end

  @impl true
  def handle_call({:internal_api_issuer_jwks, issuer_name}, _from, state) do
    {:reply, state[:internal_api][:issuer_jwks][issuer_name], state}
  end

  defp build_issuer_jwks(api_authentication_scope) do
    Application.fetch_env!(:neurow, api_authentication_scope)[:issuers]
    |> Enum.map(fn {issuer_name, shared_secrets} ->
      {to_string(issuer_name),
       case is_list(shared_secrets) do
         true ->
           shared_secrets |> Enum.map(fn shared_secret -> JOSE.JWK.from_oct(shared_secret) end)

         false ->
           [JOSE.JWK.from_oct(shared_secrets)]
       end}
    end)
    |> Map.new()
  end
end
