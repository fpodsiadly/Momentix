defmodule Momentix.Match.Tree do
  @moduledoc """
  Per-match supervision tree containing all data sources for a fixture.
  """

  use Supervisor

  alias Momentix.Match.Names
  alias Momentix.{MatchClockServer, ScoreServer, StatsServer, EventsServer, PlayerSupervisor}

  def start_link(opts) do
    match_id = Keyword.fetch!(opts, :match_id)
    Supervisor.start_link(__MODULE__, opts, name: Names.via(match_id, __MODULE__))
  end

  @impl true
  def init(opts) do
    match_id = Keyword.fetch!(opts, :match_id)

    children = [
      {MatchClockServer, match_id: match_id},
      {ScoreServer, match_id: match_id},
      {StatsServer, match_id: match_id},
      {EventsServer, match_id: match_id},
      {PlayerSupervisor, match_id: match_id}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
