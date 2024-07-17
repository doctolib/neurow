defmodule NeurowTest do
  use ExUnit.Case
  doctest Neurow

  test "greets the world" do
    assert Neurow.hello() == :world
  end
end
