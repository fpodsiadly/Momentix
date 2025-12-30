defmodule Momentix.PlayerServer do
  @moduledoc """
  Tracks per-player ratings and broadcasts updates to LiveView.
  """

  use GenServer
  require Logger

  alias Momentix.Match.Names

  @default_client Momentix.Api.Client

  @poll_ms 7_000

  def start_link(opts) do
    match_id = Keyword.fetch!(opts, :match_id)
    player_id = Keyword.fetch!(opts, :player_id)

    GenServer.start_link(__MODULE__, %{match_id: match_id, player_id: player_id, opts: opts},
      name: Names.via(match_id, {:player, player_id})
    )
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

    schedule_poll(poll_ms)

    {:ok,
     state
     |> Map.put(:poll_ms, poll_ms)
     |> Map.put(:client, client)
     |> Map.put(:rating, nil)
     |> Map.delete(:opts)}
  end

  @impl true
  def handle_info(
        :poll,
        %{match_id: match_id, player_id: player_id, client: client, poll_ms: poll_ms} = state
      ) do
    state =
      case client.fetch_players(match_id) do
        {:ok, players} ->
          case Enum.find(players, &(&1.id == to_string(player_id))) do
            nil ->
              state

            player ->
              Phoenix.PubSub.broadcast(
                Momentix.PubSub,
                "match:#{match_id}:players",
                {:player, player}
              )

              %{state | rating: player.rating}
          end

        {:error, reason} ->
          Logger.debug("player poll skipped: #{inspect(reason)}")
          state
      end

    schedule_poll(poll_ms)
    {:noreply, state}
  end

  defp schedule_poll(poll_ms), do: Process.send_after(self(), :poll, poll_ms)
end
