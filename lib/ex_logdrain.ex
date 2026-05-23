defmodule ExLogdrain.Application do
  use Application

  @impl true
  def start(_type, _args) do
    port = System.get_env("PORT", "4000") |> String.to_integer()

    children = [
      {ExLogdrain.Repo, []},
      {ExLogdrain.LogBuffer, []},
      {Bandit, plug: ExLogdrain.Router, port: port, thousand_island_options: [shutdown_timeout: 15_000]}
    ]

    opts = [strategy: :one_for_one, name: ExLogdrain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
