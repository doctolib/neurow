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
    {:ok, %{public_issuer_jwks: build_public_issuer_jwks(), internal_issuer_jwks: build_internal_issuer_jwks()}}
  end

  @impl true
  def handle_call({:public_issuer_jwks, issuer_name},  _from, state) do
    {:reply, state[:public_issuer_jwks][issuer_name], state}
  end

  @impl true
  def handle_call({:internal_issuer_jwks, issuer_name},  _from, state) do
    {:reply, state[:internal_issuer_jwks][issuer_name], state}
  end

  defp build_public_issuer_jwks do
    Application.fetch_env!(:neurow, :public_issuers)
    |> Enum.map(fn {issuer_name, public_key} ->
      {to_string(issuer_name), JOSE.JWK.from_pem(public_key)}
    end)
    |> Map.new()
  end

  defp build_internal_issuer_jwks do
    Application.fetch_env!(:neurow, :internal_issuers)
    |> Enum.map(fn {issuer_name, shared_secret} ->
      {to_string(issuer_name), JOSE.JWK.from_oct(shared_secret)}
    end)
    |> Map.new()
  end
end
