defmodule Momentix.ScoreServer do
  @moduledoc """
  Derives scoreline from events and broadcasts lightweight score updates.
  """

  use GenServer
  require Logger

  alias Momentix.Match.Names

  @default_client Momentix.Api.Client

  @poll_ms 4_000

  def start_link(opts) do
    match_id = Keyword.fetch!(opts, :match_id)

    GenServer.start_link(__MODULE__, %{match_id: match_id, opts: opts},
      name: Names.via(match_id, __MODULE__)
    )
  end

  def poll_now(match_id) do
    match_id
    |> Names.via(__MODULE__)
    |> GenServer.call(:poll_now)
  end

  @impl true
  def init(state) do
    poll_ms = Keyword.get(state.opts, :poll_ms, @poll_ms)

    client =
      Keyword.get(
        state.opts,
        :client,
        Application.get_env(:momentix, :api_client, @default_client)
      )

    base_state =
      state
      |> Map.put(:poll_ms, poll_ms)
      |> Map.put(:client, client)
      |> Map.put(:score, %{home: 0, away: 0})
      |> Map.put(:teams, %{})
      |> Map.delete(:opts)

    schedule_poll(poll_ms)

    {:ok, poll_once(base_state)}
  end

  @impl true
  def handle_info(:poll, %{poll_ms: poll_ms} = state) do
    state = poll_once(state)

    schedule_poll(poll_ms)
    {:noreply, state}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    state = poll_once(state)
    {:reply, state.score, state}
  end

  defp maybe_broadcast(match_id, old_score, old_teams, new_score) do
    new_score_only = Map.take(new_score, [:home, :away])
    new_teams_only = Map.take(new_score, [:home_id, :away_id, :home_name, :away_name])

    if old_score != new_score_only or old_teams != new_teams_only do
      Phoenix.PubSub.broadcast(Momentix.PubSub, "match:#{match_id}:score", {:score, new_score})
    end
  end

  defp poll_once(%{match_id: match_id, client: client} = state) do
    case client.fetch_score(match_id) do
      {:ok, score} ->
        new_score = Map.take(score, [:home, :away])
        new_teams = Map.take(score, [:home_id, :away_id, :home_name, :away_name])

        maybe_broadcast(match_id, state.score, state.teams, score)

        %{state | score: new_score, teams: new_teams}

      {:error, reason} ->
        Logger.debug("score poll skipped: #{inspect(reason)}")
        state
    end
  end

  defp schedule_poll(poll_ms), do: Process.send_after(self(), :poll, poll_ms)
end
