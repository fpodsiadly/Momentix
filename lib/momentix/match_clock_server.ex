defmodule Momentix.MatchClockServer do
  @moduledoc """
  Ticks match clock and broadcasts elapsed time to LiveView via PubSub.
  """

  use GenServer

  alias Momentix.Match.Names

  @tick_ms 1_000

  def start_link(opts) do
    match_id = Keyword.fetch!(opts, :match_id)
    GenServer.start_link(__MODULE__, %{match_id: match_id}, name: Names.via(match_id, __MODULE__))
  end

  @impl true
  def init(state) do
    send(self(), :initialize)
    {:ok, Map.merge(%{offset_ms: 0, phase: :first_half}, state)}
  end

  @impl true
  def handle_info(:initialize, state) do
    schedule_tick()
    {:noreply, Map.put(state, :started_at, System.monotonic_time(:millisecond))}
  end

  @impl true
  def handle_info(:tick, %{match_id: match_id} = state) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = state.offset_ms + (now - state.started_at)

    Phoenix.PubSub.broadcast(
      Momentix.PubSub,
      "match:#{match_id}:clock",
      {:clock_tick, elapsed_ms, state.phase}
    )

    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)
end
