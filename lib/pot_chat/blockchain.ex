# lib/pot_chat/blockchain.ex
defmodule PoTChat.Blockchain do
  @moduledoc """
  Manages the blockchain - a list of blocks forming the chain.
  Provides functions for validation, querying, and modification.
  """

  alias PoTChat.Block

  @type t :: [Block.t()]

  @doc """
  Creates a new blockchain with genesis block.
  """
  def new do
    [Block.genesis()]
  end

  @doc """
  Adds a block to the chain after validation.
  """
  def add_block(chain, %Block{} = block) do
    case validate_new_block(chain, block) do
      :ok -> {:ok, [block | chain]}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates a new block against the current chain.
  """
  def validate_new_block(chain, block) do
    previous_block = latest_block(chain)

    cond do
      not Block.valid?(block, previous_block) ->
        {:error, :invalid_block_structure}

      true ->
        :ok
    end
  end

  @doc """
  Returns the latest (head) block in the chain.
  """
  def latest_block([head | _rest]), do: head
  def latest_block([]), do: nil

  @doc """
  Returns the chain in chronological order (oldest first).
  """
  def chronological(chain) do
    Enum.reverse(chain)
  end

  @doc """
  Gets blocks within a time range.
  """
  def blocks_in_time_range(chain, start_time, end_time) do
    chain
    |> Enum.filter(fn block ->
      block.timestamp >= start_time and block.timestamp <= end_time
    end)
  end

  @doc """
  Gets blocks from the previous turn (assumes fixed turn duration).
  """
  def blocks_from_previous_turn(chain, turn_duration_ms) do
    latest = latest_block(chain)
    if latest do
      start_time = latest.timestamp - turn_duration_ms
      blocks_in_time_range(chain, start_time, latest.timestamp)
    else
      []
    end
  end

  @doc """
  Extracts all message IDs from chat message blocks.
  """
  def extract_message_ids(blocks) do
    blocks
    |> Enum.filter(&(&1.block_type == :chat_message))
    |> Enum.map(fn block ->
      case block.data do
        %PoTChat.Message{message_id: id} -> id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @doc """
  Validates entire chain integrity.
  """
  def valid_chain?([_genesis]), do: true
  def valid_chain?([current | [previous | _] = rest]) do
    if Block.valid?(current, previous) do
      valid_chain?(rest)
    else
      false
    end
  end
  def valid_chain?([]), do: false

  @doc """
  Gets chain length.
  """
  def length(chain), do: Kernel.length(chain)

  @doc """
  Finds block by index.
  """
  def get_block_by_index(chain, index) do
    Enum.find(chain, &(&1.index == index))
  end

  @doc """
  Gets the last N blocks (most recent first).
  """
  def last_n_blocks(chain, n) do
    Enum.take(chain, n)
  end

  @doc """
  Replaces chain if new chain is longer and valid.
  Implements consensus: longest valid chain wins.
  """
  def replace_chain(current_chain, new_chain) do
    cond do
      length(new_chain) <= length(current_chain) ->
        {:error, :new_chain_not_longer}

      not valid_chain?(new_chain) ->
        {:error, :invalid_chain}

      true ->
        {:ok, new_chain}
    end
  end
end