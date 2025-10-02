# lib/pot_chat/message.ex
defmodule PoTChat.Message do
  @moduledoc """
  Represents a chat message before it becomes a block.
  Messages are created by any node, signed, and broadcast to all peers.
  """

  @enforce_keys [:content, :author_id, :timestamp, :signature]
  defstruct [:content, :author_id, :timestamp, :signature, :message_id]

  alias PoTChat.Crypto

  @doc """
  Creates and signs a new message.
  """
  def create(content, author_id, private_key) do
    timestamp = System.system_time(:millisecond)
    message_id = Crypto.generate_message_id(content, author_id, timestamp)
    
    # Sign the message components
    data_to_sign = signable_data(content, author_id, timestamp, message_id)
    signature = Crypto.sign(data_to_sign, private_key)

    %__MODULE__{
      content: content,
      author_id: author_id,
      timestamp: timestamp,
      signature: signature,
      message_id: message_id
    }
  end

  @doc """
  Verifies message signature.
  """
  def verify(%__MODULE__{} = message, public_key) do
    data_to_sign = signable_data(
      message.content,
      message.author_id,
      message.timestamp,
      message.message_id
    )
    
    Crypto.verify(data_to_sign, message.signature, public_key)
  end

  # Private helper to create consistent signable data
  defp signable_data(content, author_id, timestamp, message_id) do
    "#{content}|#{author_id}|#{timestamp}|#{message_id}"
  end

  @doc """
  Converts message to map for serialization.
  """
  def to_map(%__MODULE__{} = message) do
    %{
      content: message.content,
      author_id: message.author_id,
      timestamp: message.timestamp,
      signature: Base.encode64(message.signature),
      message_id: message.message_id
    }
  end

  @doc """
  Creates message from map (deserialization).
  """
  def from_map(map) do
    %__MODULE__{
      content: map["content"] || map[:content],
      author_id: map["author_id"] || map[:author_id],
      timestamp: map["timestamp"] || map[:timestamp],
      signature: Base.decode64!(map["signature"] || map[:signature]),
      message_id: map["message_id"] || map[:message_id]
    }
  end
end