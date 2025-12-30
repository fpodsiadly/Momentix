defmodule Momentix.MatchSupervisor do
  @moduledoc """
  Dynamic supervisor that owns one tree per match.
  """

  use DynamicSupervisor

  alias Momentix.Match.Tree
  alias Momentix.Match.Names

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_match(match_id, team_id \\ nil) do
    spec = {Tree, match_id: match_id, team_id: team_id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_match(match_id) do
    with [{pid, _}] <- Registry.lookup(Names.registry(), {match_id, Tree}) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    else
      [] -> :ok
    end
  end
end
