# lib/pot_chat/block.ex
defmodule PoTChat.Block do
  @moduledoc """
  Represents a block in the blockchain.
  Blocks are created by the Leading Node during their turn.
  """

  @enforce_keys [:index, :timestamp, :data, :previous_hash, :hash, :author_id, :signature]
  defstruct [:index, :timestamp, :data, :previous_hash, :hash, :author_id, :signature, :block_type]

  alias PoTChat.{Crypto, Message}

  @type block_type :: :chat_message | :lost_message_recovery | :turn_transition | :genesis

  @doc """
  Creates the genesis block (first block in chain).
  """
  def genesis do
    timestamp = System.system_time(:millisecond)
    data = %{note: "Genesis block"}
    
    block = %__MODULE__{
      index: 0,
      timestamp: timestamp,
      data: data,
      previous_hash: "0",
      hash: "",
      author_id: "genesis",
      signature: "",
      block_type: :genesis
    }

    hash = calculate_hash(block)
    %{block | hash: hash}
  end

  @doc """
  Creates a new block with a chat message.
  """
  def new_message_block(previous_block, message, author_id, private_key) do
    create_block(
      previous_block,
      message,
      author_id,
      private_key,
      :chat_message
    )
  end

  @doc """
  Creates a recovery block containing multiple lost messages.
  """
  def new_recovery_block(previous_block, messages, author_id, private_key) do
    data = %{
      recovered_messages: Enum.map(messages, &Message.to_map/1),
      note: "Recovered #{length(messages)} messages from previous turn"
    }

    create_block(
      previous_block,
      data,
      author_id,
      private_key,
      :lost_message_recovery
    )
  end

  @doc """
  Creates a turn transition marker block.
  """
  def new_transition_block(previous_block, from_node, to_node, private_key) do
    data = %{
      from: from_node,
      to: to_node,
      note: "Turn transition"
    }

    create_block(
      previous_block,
      data,
      from_node,
      private_key,
      :turn_transition
    )
  end

  # Generic block creation
  defp create_block(previous_block, data, author_id, private_key, block_type) do
    timestamp = System.system_time(:millisecond)
    
    block = %__MODULE__{
      index: previous_block.index + 1,
      timestamp: timestamp,
      data: data,
      previous_hash: previous_block.hash,
      hash: "",
      author_id: author_id,
      signature: "",
      block_type: block_type
    }

    # Calculate hash
    hash = calculate_hash(block)
    block = %{block | hash: hash}

    # Sign the block
    signature = Crypto.sign(signable_data(block), private_key)
    %{block | signature: signature}
  end

  @doc """
  Calculates block hash from its contents.
  """
  def calculate_hash(%__MODULE__{} = block) do
    data_string = inspect(block.data)
    
    Crypto.hash(
      "#{block.index}#{block.timestamp}#{data_string}#{block.previous_hash}#{block.author_id}"
    )
  end

  @doc """
  Verifies block signature.
  """
  def verify_signature(%__MODULE__{} = block, public_key) do
    Crypto.verify(signable_data(block), block.signature, public_key)
  end

  # Data that gets signed
  defp signable_data(block) do
    "#{block.index}|#{block.timestamp}|#{block.hash}|#{block.previous_hash}|#{block.author_id}"
  end

  @doc """
  Validates block structure and relationships.
  """
  def valid?(%__MODULE__{} = block, previous_block) do
    with true <- block.index == previous_block.index + 1,
         true <- block.previous_hash == previous_block.hash,
         true <- block.hash == calculate_hash(block) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Converts block to map for serialization.
  """
  def to_map(%__MODULE__{} = block) do
    %{
      index: block.index,
      timestamp: block.timestamp,
      data: block.data,
      previous_hash: block.previous_hash,
      hash: block.hash,
      author_id: block.author_id,
      signature: Base.encode64(block.signature),
      block_type: block.block_type
    }
  end
end