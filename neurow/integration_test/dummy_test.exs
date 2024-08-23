defmodule DummyTest do
  use ExUnit.Case

  setup do
    IO.puts(inspect(Neurow.IntegrationTest.TestCluster.start_nodes()))
    :ok
  end

  test "this is a test" do
    IO.puts("This is a test")
  end

  test "this is another test" do
    IO.puts("This is another test")
  end
end
