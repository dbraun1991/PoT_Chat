# lib/pot_chat/application.ex
defmodule PoTChat.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # PubSub for message broadcasting
      {Phoenix.PubSub, name: PoTChat.PubSub},

      # Registry for turn managers
      {Registry, keys: :unique, name: PoTChat.Registry},

      # Node supervisor (will start turn managers dynamically)
      PoTChat.NodeSupervisor
    ]

    opts = [strategy: :one_for_one, name: PoTChat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
