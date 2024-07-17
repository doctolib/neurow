defmodule Neurow.Configuration do
  use GenServer

  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  def public_issuer_jwks(issuer_name) do
    GenServer.call(__MODULE__, {:public_issuer_jwks, issuer_name})
  end

  def internal_issuer_jwks(issuer_name) do
    GenServer.call(__MODULE__, {:internal_issuer_jwks, issuer_name})
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       public_issuer_jwks: build_issuer_jwks(:public_issuers),
       internal_issuer_jwks: build_issuer_jwks(:internal_issuers)
     }}
  end

  @impl true
  def handle_call({:public_issuer_jwks, issuer_name}, _from, state) do
    {:reply, state[:public_issuer_jwks][issuer_name], state}
  end

  @impl true
  def handle_call({:internal_issuer_jwks, issuer_name}, _from, state) do
    {:reply, state[:internal_issuer_jwks][issuer_name], state}
  end

  defp build_issuer_jwks(issuers_scope) do
    Application.fetch_env!(:neurow, issuers_scope)
    |> Enum.map(fn {issuer_name, shared_secret} ->
      {to_string(issuer_name), JOSE.JWK.from_oct(shared_secret)}
    end)
    |> Map.new()
  end
end
