defmodule Momentix.TestSupport.FakeApiClient do
  @moduledoc """
  Lightweight in-memory client used to stub API-Football responses in tests.
  """

  @keys [:events, :stats, :players, :score, :matches]

  def reset do
    Enum.each(@keys, &:persistent_term.erase({__MODULE__, &1}))
    :ok
  end

  def put_events(events), do: :persistent_term.put({__MODULE__, :events}, events)
  def put_stats(stats), do: :persistent_term.put({__MODULE__, :stats}, stats)
  def put_players(players), do: :persistent_term.put({__MODULE__, :players}, players)
  def put_score(score), do: :persistent_term.put({__MODULE__, :score}, score)
  def put_matches(matches), do: :persistent_term.put({__MODULE__, :matches}, matches)

  def fetch_live_matches(_team_id, _opts \ []), do: {:ok, lookup(:matches, [])}

  def fetch_events(_match_id, _opts \\ []), do: {:ok, lookup(:events, [])}

  def fetch_stats(_match_id, _opts \\ []) do
    stats = lookup(:stats, %{})
    {:ok, %{stats: stats, momentum: momentum_from_stats(stats)}}
  end

  def fetch_players(_match_id, _opts \\ []), do: {:ok, lookup(:players, [])}
  def fetch_score(_match_id, _opts \\ []), do: {:ok, lookup(:score, %{home: 0, away: 0})}

  defp lookup(key, default), do: :persistent_term.get({__MODULE__, key}, default)

  defp momentum_from_stats(stats) when map_size(stats) == 0, do: []

  defp momentum_from_stats(stats) do
    Enum.map(stats, fn {team, stat_map} ->
      shot_total = Map.get(stat_map, "Total Shots", 0)
      poss = Map.get(stat_map, "Ball Possession", 0)
      %{team: team, value: shot_total * 0.6 + poss * 0.4}
    end)
  end
end
