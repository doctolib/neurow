defmodule Neurow.IntegrationTest.MessageBrokeringTest do
  use ExUnit.Case
  use Plug.Test

  @moduletag :integration_test

  describe "topics subscriptions" do
    test "subscriber only receives messages for the topic it subscribes to" do
    end

    test "messages are delivered to all subscribers of a topic" do
    end
  end

  describe "message publishing" do
    test "delivers messages to multiple topics in one call to the internal API" do
    end

    test "delivers multiple messages to a single topic in one call to the internal API" do
    end

    test "delivers multiple messages to a mulitple topics in one call to the internal API" do
    end
  end
end
