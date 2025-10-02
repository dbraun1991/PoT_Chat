# lib/pot_chat/node_supervisor.ex
defmodule PoTChat.NodeSupervisor do
  @moduledoc """
  Supervisor for dynamically starting turn manager nodes.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new node participant.
  """
  def start_node(node_id, peer_ids, peer_public_keys) do
    child_spec = %{
      id: PoTChat.TurnManager,
      start: {
        PoTChat.TurnManager,
        :start_link,
        [[
          node_id: node_id,
          peer_ids: peer_ids,
          peer_public_keys: peer_public_keys
        ]]
      },
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
