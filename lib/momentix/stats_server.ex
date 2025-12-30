defmodule Momentix.StatsServer do
  @moduledoc """
  Polls match statistics and broadcasts stat updates and momentum payloads.
  """

  use GenServer
  require Logger

  alias Momentix.Match.Names
  alias Momentix.PlayerSupervisor

  @default_client Momentix.Api.Client

  @poll_ms 5_000

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
      |> Map.put(:stats, %{})
      |> Map.put(:players_initialized?, false)
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
    {:reply, state.stats, state}
  end

  defp poll_once(%{match_id: match_id, client: client} = state) do
    case client.fetch_stats(match_id) do
      {:ok, %{stats: stats, momentum: momentum} = payload} ->
        Phoenix.PubSub.broadcast(Momentix.PubSub, "match:#{match_id}:stats", {:stats, payload})

        Phoenix.PubSub.broadcast(
          Momentix.PubSub,
          "match:#{match_id}:momentum",
          {:momentum, momentum}
        )

        state
        |> maybe_init_players(client, match_id)
        |> Map.put(:stats, stats)

      {:error, reason} ->
        Logger.debug("stats poll skipped: #{inspect(reason)}")
        state
    end
  end

  defp maybe_init_players(%{players_initialized?: true} = state, _client, _match_id), do: state

  defp maybe_init_players(state, client, match_id) do
    case client.fetch_players(match_id) do
      {:ok, players} ->
        Phoenix.PubSub.broadcast(
          Momentix.PubSub,
          "match:#{match_id}:players",
          {:players, players}
        )

        PlayerSupervisor.start_lineup(match_id, Enum.map(players, & &1.id))
        %{state | players_initialized?: true}

      _ ->
        state
    end
  end

  defp schedule_poll(poll_ms), do: Process.send_after(self(), :poll, poll_ms)
end
