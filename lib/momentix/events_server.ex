defmodule Momentix.EventsServer do
  @moduledoc """
  Polls API-Football events for a match and broadcasts new ones over PubSub.
  """

  use GenServer
  require Logger

  alias Momentix.Match.Names

  @default_client Momentix.Api.Client

  @poll_ms 3_000

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
      |> Map.put(:last_seen_ids, MapSet.new())
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
    {:reply, state.last_seen_ids, state}
  end

  defp poll_once(%{match_id: match_id, client: client} = state) do
    case client.fetch_events(match_id) do
      {:ok, events} ->
        new_ids = broadcast_new(match_id, events, state.last_seen_ids)
        %{state | last_seen_ids: new_ids}

      {:error, reason} ->
        Logger.debug("events poll skipped: #{inspect(reason)}")
        state
    end
  end

  defp broadcast_new(match_id, events, seen_ids) do
    Enum.reduce(events, seen_ids, fn event, acc_ids ->
      id = event[:id] || event["id"] || System.unique_integer([:positive])

      if MapSet.member?(acc_ids, id) do
        acc_ids
      else
        Phoenix.PubSub.broadcast(
          Momentix.PubSub,
          "match:#{match_id}:events",
          {:event, Map.put(event, :id, id)}
        )

        MapSet.put(acc_ids, id)
      end
    end)
  end

  defp schedule_poll(poll_ms), do: Process.send_after(self(), :poll, poll_ms)
end
