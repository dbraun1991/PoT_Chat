# lib/pot_chat/turn_manager.ex
defmodule PoTChat.TurnManager do
  @moduledoc """
  Manages the round-robin turn rotation and timing.
  Controls when nodes can write blocks and handles turn transitions.
  """

  use GenServer
  require Logger

  alias PoTChat.{Blockchain, Block, Message, MessagePool, Crypto}

  @turn_duration_ms 30_000  # 30 seconds
  @transition_duration_ms 5_000  # 5 seconds
  @message_retention_ms 120_000  # Keep messages for 2 turns

  defstruct [
    :node_id,
    :peer_ids,  # Ordered list of all node IDs (including self)
    :current_leader_index,
    :turn_start_time,
    :state,  # :waiting | :leading | :transition
    :blockchain,
    :message_pool,
    :keypair,  # {public_key, private_key}
    :peer_public_keys,  # Map of node_id => public_key
    :turn_timer_ref,
    :pending_own_messages  # Messages I want to send during my turn
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:node_id]))
  end

  defp via_tuple(node_id) do
    {:via, Registry, {PoTChat.Registry, {:turn_manager, node_id}}}
  end

  @doc """
  Submit a chat message (can be called by any node at any time).
  """
  def send_message(node_id, content) do
    GenServer.call(via_tuple(node_id), {:send_message, content})
  end

  @doc """
  Get current blockchain state.
  """
  def get_blockchain(node_id) do
    GenServer.call(via_tuple(node_id), :get_blockchain)
  end

  @doc """
  Get current turn state.
  """
  def get_state(node_id) do
    GenServer.call(via_tuple(node_id), :get_state)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    node_id = Keyword.fetch!(opts, :node_id)
    peer_ids = Keyword.fetch!(opts, :peer_ids)
    peer_public_keys = Keyword.fetch!(opts, :peer_public_keys)

    # Generate keypair for this node
    {public_key, private_key} = Crypto.generate_keypair()

    # Subscribe to message broadcasts
    Phoenix.PubSub.subscribe(PoTChat.PubSub, "pot:messages")
    Phoenix.PubSub.subscribe(PoTChat.PubSub, "pot:blocks")

    state = %__MODULE__{
      node_id: node_id,
      peer_ids: peer_ids,
      current_leader_index: 0,
      turn_start_time: nil,
      state: :waiting,
      blockchain: Blockchain.new(),
      message_pool: MessagePool.new(),
      keypair: {public_key, private_key},
      peer_public_keys: peer_public_keys,
      turn_timer_ref: nil,
      pending_own_messages: []
    }

    # If we're the first node, start as leader
    if am_i_leader?(state) do
      Logger.info("[#{node_id}] Starting as initial leader")
      {:ok, start_turn(state)}
    else
      Logger.info("[#{node_id}] Starting as follower, waiting for turn")
      {:ok, state}
    end
  end

  @impl true
  def handle_call({:send_message, content}, _from, state) do
    {_public_key, private_key} = state.keypair
    message = Message.create(content, state.node_id, private_key)

    # Broadcast to all peers (including self)
    Phoenix.PubSub.broadcast(
      PoTChat.PubSub,
      "pot:messages",
      {:new_message, message}
    )

    Logger.info("[#{state.node_id}] Sent message: #{content}")

    {:reply, {:ok, message.message_id}, state}
  end

  @impl true
  def handle_call(:get_blockchain, _from, state) do
    {:reply, state.blockchain, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      node_id: state.node_id,
      state: state.state,
      current_leader: current_leader(state),
      blockchain_length: Blockchain.length(state.blockchain),
      pending_messages: MessagePool.pending_count(state.message_pool)
    }
    {:reply, info, state}
  end

  # Handle incoming messages (from any node)
  @impl true
  def handle_info({:new_message, message}, state) do
    # Verify signature
    author_public_key = Map.get(state.peer_public_keys, message.author_id)

    if author_public_key && Message.verify(message, author_public_key) do
      # Add to message pool
      pool = MessagePool.add(state.message_pool, message)
      state = %{state | message_pool: pool}

      Logger.debug("[#{state.node_id}] Received valid message from #{message.author_id}")

      # If I'm the leader, I'll publish this during my turn
      {:noreply, state}
    else
      Logger.warn("[#{state.node_id}] Received invalid message from #{message.author_id}")
      {:noreply, state}
    end
  end

  # Handle incoming blocks (from leader)
  @impl true
  def handle_info({:new_block, block}, state) do
    case Blockchain.add_block(state.blockchain, block) do
      {:ok, new_chain} ->
        # Mark message as included if it's a chat message
        pool = case block.block_type do
          :chat_message ->
            message = block.data
            MessagePool.mark_included(state.message_pool, message.message_id)
          :lost_message_recovery ->
            # Mark all recovered messages as included
            recovered = block.data.recovered_messages
            Enum.reduce(recovered, state.message_pool, fn msg_map, pool ->
              msg = Message.from_map(msg_map)
              MessagePool.mark_included(pool, msg.message_id)
            end)
          _ ->
            state.message_pool
        end

        Logger.debug("[#{state.node_id}] Added block ##{block.index}")
        {:noreply, %{state | blockchain: new_chain, message_pool: pool}}

      {:error, reason} ->
        Logger.warn("[#{state.node_id}] Failed to add block: #{reason}")
        {:noreply, state}
    end
  end

  # Turn timer expired - end current turn
  @impl true
  def handle_info(:turn_timeout, %{state: :leading} = state) do
    Logger.info("[#{state.node_id}] Turn timeout - publishing pending messages")
    state = publish_pending_messages(state)
    state = enter_transition(state)
    {:noreply, state}
  end

  # Transition timer expired - move to next leader
  @impl true
  def handle_info(:transition_timeout, %{state: :transition} = state) do
    Logger.info("[#{state.node_id}] Transition complete")
    state = advance_to_next_leader(state)
    {:noreply, state}
  end

  # Periodic cleanup of old messages
  @impl true
  def handle_info(:cleanup, state) do
    pool = MessagePool.cleanup(state.message_pool, @message_retention_ms)
    Process.send_after(self(), :cleanup, 60_000)  # Cleanup every minute
    {:noreply, %{state | message_pool: pool}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private Functions

  defp start_turn(state) do
    Logger.info("[#{state.node_id}] Starting turn as leader")

    # Check for missing messages from previous turn
    state = check_and_recover_messages(state)

    # Schedule turn end
    ref = Process.send_after(self(), :turn_timeout, @turn_duration_ms)

    %{state |
      state: :leading,
      turn_start_time: System.system_time(:millisecond),
      turn_timer_ref: ref
    }
  end

  defp check_and_recover_messages(state) do
    # Get blocks from previous turn
    prev_turn_blocks = Blockchain.blocks_from_previous_turn(
      state.blockchain,
      @turn_duration_ms
    )

    # Find which messages are included in those blocks
    included_message_ids = Blockchain.extract_message_ids(prev_turn_blocks)

    # Get messages I saw during previous turn
    turn_end = System.system_time(:millisecond)
    turn_start = turn_end - @turn_duration_ms - @transition_duration_ms

    messages_i_saw = MessagePool.messages_in_time_range(
      state.message_pool,
      turn_start,
      turn_end
    )

    # Find missing messages
    missing = Enum.reject(messages_i_saw, fn msg ->
      MapSet.member?(included_message_ids, msg.message_id)
    end)

    if length(missing) > 0 do
      Logger.warn("[#{state.node_id}] Recovering #{length(missing)} missing messages")
      publish_recovery_block(state, missing)
    else
      state
    end
  end

  defp publish_recovery_block(state, missing_messages) do
    {_public_key, private_key} = state.keypair
    latest = Blockchain.latest_block(state.blockchain)

    recovery_block = Block.new_recovery_block(
      latest,
      missing_messages,
      state.node_id,
      private_key
    )

    # Add to own chain
    {:ok, new_chain} = Blockchain.add_block(state.blockchain, recovery_block)

    # Broadcast to network
    Phoenix.PubSub.broadcast(
      PoTChat.PubSub,
      "pot:blocks",
      {:new_block, recovery_block}
    )

    # Mark recovered messages as included
    pool = Enum.reduce(missing_messages, state.message_pool, fn msg, pool ->
      MessagePool.mark_included(pool, msg.message_id)
    end)

    %{state | blockchain: new_chain, message_pool: pool}
  end

  defp publish_pending_messages(state) do
    pending = MessagePool.pending_messages(state.message_pool)
    {_public_key, private_key} = state.keypair

    # Publish each pending message as a block
    Enum.reduce(pending, state, fn message, acc_state ->
      publish_message_block(acc_state, message, private_key)
    end)
  end

  defp publish_message_block(state, message, private_key) do
    latest = Blockchain.latest_block(state.blockchain)

    block = Block.new_message_block(
      latest,
      message,
      state.node_id,
      private_key
    )

    # Add to own chain
    {:ok, new_chain} = Blockchain.add_block(state.blockchain, block)

    # Broadcast
    Phoenix.PubSub.broadcast(
      PoTChat.PubSub,
      "pot:blocks",
      {:new_block, block}
    )

    # Mark as included
    pool = MessagePool.mark_included(state.message_pool, message.message_id)

    Logger.info("[#{state.node_id}] Published block ##{block.index} with message from #{message.author_id}")

    %{state | blockchain: new_chain, message_pool: pool}
  end

  defp enter_transition(state) do
    # Cancel turn timer if exists
    if state.turn_timer_ref do
      Process.cancel_timer(state.turn_timer_ref)
    end

    # Schedule transition end
    ref = Process.send_after(self(), :transition_timeout, @transition_duration_ms)

    Logger.info("[#{state.node_id}] Entering transition phase")

    %{state | state: :transition, turn_timer_ref: ref}
  end

  defp advance_to_next_leader(state) do
    # Move to next leader in round-robin
    next_index = rem(state.current_leader_index + 1, length(state.peer_ids))

    state = %{state |
      current_leader_index: next_index,
      turn_timer_ref: nil
    }

    if am_i_leader?(state) do
      start_turn(state)
    else
      Logger.info("[#{state.node_id}] Now waiting, leader is #{current_leader(state)}")
      %{state | state: :waiting}
    end
  end

  defp am_i_leader?(state) do
    current_leader(state) == state.node_id
  end

  defp current_leader(state) do
    Enum.at(state.peer_ids, state.current_leader_index)
  end
end
