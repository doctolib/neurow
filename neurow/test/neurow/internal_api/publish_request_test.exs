defmodule Neurow.InternalApi.PublishRequestTest do
  use ExUnit.Case

  alias Neurow.InternalApi.PublishRequest

  describe "#validate_topics" do
    test "returns an error if 'topic' and 'topics' attributes are not provided" do
      request =
        PublishRequest.from_json(%{"message" => default_json_message()})

      assert PublishRequest.validate_topics(request) ==
               {:error, "Attribute 'topic' or 'topics' is expected"}
    end

    test "returns an error if both 'topic' and 'topics' attributes are provided" do
      request =
        PublishRequest.from_json(%{"message" => default_json_message()})

      assert PublishRequest.validate_topics(request) ==
               {:error, "Attribute 'topic' or 'topics' is expected"}
    end

    test "returns an error if 'topic' is provided, but is not a string" do
      request =
        PublishRequest.from_json(%{
          "topic" => 1234,
          "message" => default_json_message()
        })

      assert PublishRequest.validate_topics(request) ==
               {:error, "'topic' must be a non-empty string"}
    end

    test "returns an error if 'topic' is provided, but is an empty string" do
      request =
        PublishRequest.from_json(%{
          "topic" => "",
          "message" => default_json_message()
        })

      assert PublishRequest.validate_topics(request) ==
               {:error, "'topic' must be a non-empty string"}
    end

    test "returns an error if 'topics' is provided, but is not an array" do
      request =
        PublishRequest.from_json(%{
          "topics" => "test-topic",
          "message" => default_json_message()
        })

      assert PublishRequest.validate_topics(request) ==
               {:error, "'topics' must be an non-empty array of non-empty strings"}
    end

    test "returns an error if 'topics' is provided, but is not an array of strings" do
      request =
        PublishRequest.from_json(%{
          "topics" => ["test-topic", 123],
          "message" => default_json_message()
        })

      assert PublishRequest.validate_topics(request) ==
               {:error, "'topics' must be an non-empty array of non-empty strings"}
    end

    test "returns an error if 'topics' is provided, is an empty array" do
      request =
        PublishRequest.from_json(%{
          "topics" => [],
          "message" => default_json_message()
        })

      assert PublishRequest.validate_topics(request) ==
               {:error, "'topics' must be an non-empty array of non-empty strings"}
    end

    test "returns an error if 'topics' is provided, is an array of strings, but one of them is empty" do
      request =
        PublishRequest.from_json(%{
          "topics" => ["test-topic", "", 123],
          "message" => default_json_message()
        })

      assert PublishRequest.validate_topics(request) ==
               {:error, "'topics' must be an non-empty array of non-empty strings"}
    end

    test "is valid if 'topic' is provided and is a string" do
      request =
        PublishRequest.from_json(%{
          "topic" => "test-topic",
          "message" => default_json_message()
        })

      assert PublishRequest.validate_topics(request) == :ok
    end

    test "is valid if 'topics' is provided and is an array of string" do
      request =
        PublishRequest.from_json(%{
          "topics" => ["test-topic1", "test-topic2"],
          "message" => default_json_message()
        })

      assert PublishRequest.validate_topics(request) == :ok
    end
  end

  describe "#validate_messages" do
    test "returns an error if 'message' and 'messages' attributes are not provided" do
      request =
        PublishRequest.from_json(%{
          "topic" => "test-topic"
        })

      assert PublishRequest.validate_messages(request) ==
               {:error, "Attribute 'message' or 'messages' is expected"}
    end

    test "returns an error if both 'message' and 'messages' are provided" do
      request =
        PublishRequest.from_json(%{
          "topic" => "test-topic",
          "message" => default_json_message(),
          "messages" => [default_json_message()]
        })

      assert PublishRequest.validate_messages(request) ==
               {:error, "Attribute 'message' or 'messages' is expected"}
    end

    test "returns an error if 'message' value is not a valid message" do
      request =
        PublishRequest.from_json(%{
          "topic" => "test-topic",
          "message" => bad_json_message()
        })

      assert PublishRequest.validate_messages(request) ==
               {:error, "'event' must be a non-empty string"}
    end

    test "returns an error if 'messages' is an empty array" do
      request =
        PublishRequest.from_json(%{
          "topic" => "test-topic",
          "messages" => []
        })

      assert PublishRequest.validate_messages(request) ==
               {:error, "'messages' must be a non-empty list"}
    end

    test "returns an error if 'messages' contain a invalid message" do
      request =
        PublishRequest.from_json(%{
          "topic" => "test-topic",
          "messages" => [default_json_message(), bad_json_message()]
        })

      assert PublishRequest.validate_messages(request) ==
               {:error, "'event' must be a non-empty string"}
    end

    test "returns :ok if 'message' is valid" do
      request =
        PublishRequest.from_json(%{
          "topic" => "test-topic",
          "message" => default_json_message()
        })

      assert PublishRequest.validate_messages(request) == :ok
    end

    test "returns :ok if 'messages' is a list of valid messages" do
      request =
        PublishRequest.from_json(%{
          "topic" => "test-topic",
          "messages" => [default_json_message(), default_json_message()]
        })

      assert PublishRequest.validate_messages(request) == :ok
    end
  end

  describe "#validate" do
  end

  defp default_json_message(),
    do: %{
      "event" => "event-test",
      "payload" => "Test payload",
      "timestamp" => :os.system_time(:millisecond)
    }

  defp bad_json_message(),
    do: %{
      default_json_message()
      | "event" => 1234
    }
end
