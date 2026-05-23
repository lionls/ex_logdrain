defmodule ExLogdrain.Application do
  use Application

  @moduledoc """
  Documentation for `ExLogdrain`.
  """

  @impl true
  def start(_type, _args) do
    children = [
      {ExLogdrain.Repo, []},
      {ExLogdrain.LogBuffer, []},
      {Bandit, plug: ExLogdrain.Router, port: 4000}
    ]

    opts = [strategy: :one_for_one, name: ExLogdrain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
