# lib/pot_chat/message_pool.ex
defmodule PoTChat.MessagePool do
  @moduledoc """
  Maintains a pool of pending messages that haven't been included in blocks yet.
  Each node maintains their own pool to track what messages they've seen.
  """

  defstruct messages: %{}, seen_in_blocks: MapSet.new()

  alias PoTChat.Message

  @type t :: %__MODULE__{
    messages: %{String.t() => {Message.t(), integer()}},
    seen_in_blocks: MapSet.t(String.t())
  }

  @doc """
  Creates a new empty message pool.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Adds a message to the pool with timestamp when seen.
  """
  def add(%__MODULE__{} = pool, %Message{} = message) do
    seen_at = System.system_time(:millisecond)
    
    messages = Map.put(pool.messages, message.message_id, {message, seen_at})
    %{pool | messages: messages}
  end

  @doc """
  Marks a message as included in a block.
  """
  def mark_included(%__MODULE__{} = pool, message_id) do
    seen_in_blocks = MapSet.put(pool.seen_in_blocks, message_id)
    %{pool | seen_in_blocks: seen_in_blocks}
  end

  @doc """
  Gets all messages seen during a time range.
  """
  def messages_in_time_range(%__MODULE__{} = pool, start_time, end_time) do
    pool.messages
    |> Enum.filter(fn {_id, {_msg, seen_at}} ->
      seen_at >= start_time and seen_at <= end_time
    end)
    |> Enum.map(fn {_id, {msg, _seen_at}} -> msg end)
  end

  @doc """
  Gets messages that haven't been included in blocks yet.
  """
  def pending_messages(%__MODULE__{} = pool) do
    pool.messages
    |> Enum.reject(fn {id, _} -> MapSet.member?(pool.seen_in_blocks, id) end)
    |> Enum.map(fn {_id, {msg, _seen_at}} -> msg end)
  end

  @doc """
  Finds messages that should have been included but weren't.
  Returns messages seen during time range that aren't marked as included.
  """
  def find_missing(%__MODULE__{} = pool, start_time, end_time) do
    messages_in_time_range(pool, start_time, end_time)
    |> Enum.reject(fn msg ->
      MapSet.member?(pool.seen_in_blocks, msg.message_id)
    end)
  end

  @doc """
  Cleans up old messages (older than retention_ms).
  """
  def cleanup(%__MODULE__{} = pool, retention_ms) do
    cutoff_time = System.system_time(:millisecond) - retention_ms
    
    messages = 
      pool.messages
      |> Enum.reject(fn {_id, {_msg, seen_at}} -> seen_at < cutoff_time end)
      |> Map.new()

    %{pool | messages: messages}
  end

  @doc """
  Checks if a message is in the pool.
  """
  def has_message?(%__MODULE__{} = pool, message_id) do
    Map.has_key?(pool.messages, message_id)
  end

  @doc """
  Gets a specific message by ID.
  """
  def get_message(%__MODULE__{} = pool, message_id) do
    case Map.get(pool.messages, message_id) do
      {message, _seen_at} -> message
      nil -> nil
    end
  end

  @doc """
  Returns count of pending messages.
  """
  def pending_count(%__MODULE__{} = pool) do
    pool.messages
    |> Enum.count(fn {id, _} -> not MapSet.member?(pool.seen_in_blocks, id) end)
  end
end