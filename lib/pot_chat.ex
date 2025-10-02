# lib/pot_chat.ex
defmodule PoTChat do
  @moduledoc """
  Main API for PoTChat - a distributed chat using Proof-of-Turn consensus.
  """

  alias PoTChat.{NodeSupervisor, TurnManager, Crypto}

  @doc """
  Starts a 5-node chat network for testing.
  Returns map of node_id => public_key
  """
  def start_test_network do
    # Generate keypairs for all nodes
    node_ids = ["alice", "bob", "carol", "dave", "eve"]
    
    keypairs = 
      Enum.map(node_ids, fn id ->
        {pub, _priv} = Crypto.generate_keypair()
        {id, pub}
      end)
      |> Map.new()

    # Start each node
    Enum.each(node_ids, fn node_id ->
      NodeSupervisor.start_node(node_id, node_ids, keypairs)
    end)

    keypairs
  end

  @doc """
  Send a chat message from a node.
  """
  def send_message(node_id, content) do
    TurnManager.send_message(node_id, content)
  end

  @doc """
  Get the blockchain from a node.
  """
  def get_blockchain(node_id) do
    TurnManager.get_blockchain(node_id)
  end

  @doc """
  Get current state of a node.
  """
  def get_state(node_id) do
    TurnManager.get_state(node_id)
  end

  @doc """
  Pretty print the blockchain from a node.
  """
  def print_chain(node_id) do
    chain = get_blockchain(node_id)
    
    IO.puts("\n=== Blockchain for #{node_id} ===")
    IO.puts("Length: #{PoTChat.Blockchain.length(chain)}\n")

    chain
    |> PoTChat.Blockchain.chronological()
    |> Enum.each(fn block ->
      IO.puts("Block ##{block.index} [#{block.block_type}]")
      IO.puts("  Author: #{block.author_id}")
      IO.puts("  Hash: #{String.slice(block.hash, 0, 8)}...")
      
      case block.block_type do
        :chat_message ->
          msg = block.data
          IO.puts("  Message: \"#{msg.content}\" from #{msg.author_id}")
        :lost_message_recovery ->
          count = length(block.data.recovered_messages)
          IO.puts("  Recovered #{count} messages")
        _ ->
          IO.puts("  Data: #{inspect(block.data)}")
      end
      
      IO.puts("")
    end)
  end
end