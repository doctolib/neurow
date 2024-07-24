defmodule Neurow.InternalApi.MessageTest do
  use ExUnit.Case
  alias Neurow.InternalApi.Message

  describe "#validate" do
    test "returns :ok if the message without a timestamp is valid" do
      message =
        Message.from_json(%{
          "event" => "test-event",
          "payload" => "Hello !"
        })

      assert Message.validate(message) == :ok
    end

    test "returns :ok if the message with a timestamp is valid" do
      message =
        Message.from_json(%{
          "event" => "test-event",
          "payload" => "Hello !",
          "timestamp" => 1234
        })

      assert Message.validate(message) == :ok
    end

    test "returns an error if 'event' is missing" do
      message =
        Message.from_json(%{
          "payload" => "Hello !",
          "timestamp" => 1234
        })

      assert Message.validate(message) == {:error, "'event' is expected"}
    end

    test "returns an error if 'event' is not a string" do
      message =
        Message.from_json(%{
          "event" => 123,
          "payload" => "Hello !",
          "timestamp" => 1234
        })

      assert Message.validate(message) == {:error, "'event' must be a non-empty string"}
    end

    test "returns an error if the payload is missing" do
      message =
        Message.from_json(%{
          "event" => "test_event",
          "timestamp" => 1234
        })

      assert Message.validate(message) == {:error, "'payload' is expected"}
    end

    test "returns an error if the payload is not a string" do
      message =
        Message.from_json(%{
          "event" => "test_event",
          "payload" => 1234,
          "timestamp" => 1234
        })

      assert Message.validate(message) == {:error, "'payload' must be a non-empty string"}
    end

    test "returns an error if the timestamp is not an integer" do
      message =
        Message.from_json(%{
          "event" => "test_event",
          "payload" => "test payload",
          "timestamp" => "foo"
        })

      assert Message.validate(message) == {:error, "'timestamp' must be a positive integer"}
    end

    test "returns an error if the timestamp is a negative integer " do
      message =
        Message.from_json(%{
          "event" => "test_event",
          "payload" => "test payload",
          "timestamp" => -1
        })

      assert Message.validate(message) == {:error, "'timestamp' must be a positive integer"}
    end
  end
end
