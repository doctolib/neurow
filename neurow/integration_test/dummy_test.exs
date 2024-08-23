defmodule DummyTest do
  use ExUnit.Case

  setup do
    Neurow.IntegrationTest.TestCluster.start_nodes()
    {:ok, cluster_state: Neurow.IntegrationTest.TestCluster.cluster_state()}
  end

  test "this is a test", context do
    IO.puts("This is a test")
    IO.puts(inspect(context.cluster_state))
  end

  test "this is another test", context do
    IO.puts("This is another test")
    IO.puts(inspect(context.cluster_state))
  end
end
