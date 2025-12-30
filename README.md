# Momentix

Realtime football match dashboard built with Phoenix LiveView. Focused on fast, fault-tolerant ingestion of API-Football data and clean UI updates via PubSub.

## System Overview

- Elixir OTP app with a per-match supervision tree.
- Processes per match: `MatchClockServer`, `ScoreServer`, `StatsServer`, `EventsServer`, `PlayerSupervisor` (dynamic), `PlayerServer` (per player).
- Data fetchers use Finch (or HTTPoison) + ETS cache + retry/backoff.
- Phoenix PubSub distributes updates; LiveView subscribes and renders.
- UI: Tailwind + daisyUI cards/tabs/badges, ApexCharts/Chart.js via LiveView hooks, Heroicons.

### Supervision Tree (per match)

```
Momentix.Application
└─ Momentix.MatchRegistry (Registry via :unique)
└─ Momentix.MatchSupervisor (DynamicSupervisor)
	 └─ start_match(match_id, team_id)
			 └─ Momentix.Match.Tree
					├─ MatchClockServer
					├─ ScoreServer
					├─ StatsServer
					├─ EventsServer
					├─ PlayerSupervisor (DynamicSupervisor)
					│   └─ PlayerServer (one per player_id)
					└─ Telemetry/Presence hooks (optional)
```

### PubSub Topics

- `"match:#{match_id}:clock"`
- `"match:#{match_id}:score"`
- `"match:#{match_id}:stats"`
- `"match:#{match_id}:events"`
- `"match:#{match_id}:player:#{player_id}"`
- `"match:#{match_id}:momentum"`

## Core Modules (OTP)

- `Momentix.MatchSupervisor` – `DynamicSupervisor` that starts/stops per-match trees.
- `Momentix.Match.Tree` – `Supervisor` that owns all match-specific servers; ensures restarts are contained.
- `Momentix.MatchClockServer` – runs the match clock (handles stoppage, halftime, added time), periodically publishes ticks.
- `Momentix.ScoreServer` – polls or listens for score changes; broadcasts goals.
- `Momentix.StatsServer` – polls detailed stats (possession, shots, xG, corners) and momentum metrics; merges deltas.
- `Momentix.EventsServer` – polls event feed (goals, cards, subs), de-dupes, orders, and broadcasts.
- `Momentix.PlayerSupervisor` – dynamic supervisor for players.
- `Momentix.PlayerServer` – per-player ratings and metrics; receives events/stats and refreshes rating.
- `Momentix.Api.Client` – Finch/HTTPoison wrapper with auth header, retry/backoff, rate-limit protection.
- `Momentix.Cache` – ETS tables (named per match) for recent payloads; TTL managed via `:ets.update_counter` or `:ets.select_delete` sweep.

### Typed Data (examples)

```elixir
@type goal :: %{
	type: :goal,
	at: non_neg_integer(), # minute (or {minute, second})
	player_id: String.t(),
	team_id: String.t(),
	assist_id: String.t() | nil,
	method: :open_play | :penalty | :free_kick | :own_goal
}

@type card :: %{
	type: :card,
	at: non_neg_integer(),
	player_id: String.t(),
	team_id: String.t(),
	color: :yellow | :red | :second_yellow,
	reason: String.t() | nil
}

@type substitution :: %{
	type: :substitution,
	at: non_neg_integer(),
	player_out_id: String.t(),
	player_in_id: String.t(),
	team_id: String.t()
}

@type stat_update :: %{
	type: :stat_update,
	possession_home: float(),
	possession_away: float(),
	xg_home: float(),
	xg_away: float(),
	shots_home: non_neg_integer(),
	shots_away: non_neg_integer(),
	corners_home: non_neg_integer(),
	corners_away: non_neg_integer()
}
```

## Example GenServer Skeletons

```elixir
defmodule Momentix.MatchClockServer do
	use GenServer
	@tick_ms 1_000

	def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: via(opts[:match_id]))

	defp via(match_id), do: {:via, Registry, {Momentix.MatchRegistry, {match_id, __MODULE__}}}

	@impl true
	def init(opts) do
		state = %{match_id: opts[:match_id], started_at: System.monotonic_time(:millisecond), offset_ms: 0, phase: :first_half}
		schedule_tick()
		{:ok, state}
	end

	@impl true
	def handle_info(:tick, state) do
		now = System.monotonic_time(:millisecond)
		elapsed_ms = state.offset_ms + (now - state.started_at)
		Phoenix.PubSub.broadcast(Momentix.PubSub, "match:#{state.match_id}:clock", {:clock_tick, elapsed_ms, state.phase})
		schedule_tick()
		{:noreply, state}
	end

	defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)
end
```

```elixir
defmodule Momentix.EventsServer do
	use GenServer
	alias Momentix.Api.Client
	@interval_ms 3_000

	def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: via(opts[:match_id]))
	defp via(match_id), do: {:via, Registry, {Momentix.MatchRegistry, {match_id, __MODULE__}}}

	@impl true
	def init(opts) do
		state = %{match_id: opts[:match_id], last_event_id: nil, cache: opts[:cache] || :match_events}
		schedule_poll()
		{:ok, state}
	end

	@impl true
	def handle_info(:poll, %{match_id: match_id} = state) do
		events = Client.fetch_events(match_id)
		{new_events, last_event_id} = dedupe(events, state.last_event_id)
		Enum.each(new_events, fn evt -> Phoenix.PubSub.broadcast(Momentix.PubSub, "match:#{match_id}:events", {:event, evt}) end)
		schedule_poll()
		{:noreply, %{state | last_event_id: last_event_id}}
	end

	defp dedupe(events, last_id) do
		events
		|> Enum.filter(&( &1.id != last_id))
		|> then(fn new -> {new, List.last(new) && List.last(new).id || last_id} end)
	end

	defp schedule_poll, do: Process.send_after(self(), :poll, @interval_ms)
end
```

## LiveView Structure

- `MomentixWeb.DashboardLive`

  - subscribes to all match topics on mount; assigns `%MatchState{}` (clock, score, stats, events, players, momentum_series}`.
  - uses `push_event/3` for chart updates (`momentum:update`, `possession:update`).
  - handles `handle_info` from PubSub to update assigns and broadcast to components via `send_update`.

- Components
  - `MomentixWeb.ScoreboardComponent` – scoreline, clock, team badges.
  - `MomentixWeb.StatsCardComponent` – cards for possession, shots, xG, corners.
  - `MomentixWeb.EventFeedComponent` – scrollable feed of events with badges.
  - `MomentixWeb.PlayerListComponent` – per-player rating, minute, cards; subscribes to player topics.

### JS Hooks (Chart.js/ApexCharts)

```javascript
let MomentumHook = {
  mounted() {
    this.chart = new ApexCharts(this.el, buildOptions())
    this.chart.render()
    this.handleEvent('momentum:update', ({ series }) =>
      this.chart.updateSeries(series)
    )
  },
  destroyed() {
    this.chart?.destroy()
  },
}

let PossessionHook = {
  mounted() {
    this.chart = new Chart(this.el, buildDoughnut())
    this.handleEvent('possession:update', ({ home, away }) => {
      this.chart.data.datasets[0].data = [home, away]
      this.chart.update()
    })
  },
}
```

## API Client and Caching

- Configure Finch pool `:api_football` with TLS and timeouts.
- `Client.fetch_live_matches(team_id)`, `fetch_events(match_id)`, `fetch_stats(match_id)`, `fetch_players(match_id)`.
- ETS cache keys: `{:events, match_id}`, `{:stats, match_id}`, `{:players, match_id}` with short TTL (5–10s) to soften rate limits.
- Use exponential backoff on HTTP 429/5xx; jittered retries.
- Map API-Football payloads into typed maps before broadcasting.

## Data Flow

1. `MatchSupervisor.start_match(match_id, team_id)` starts `Match.Tree`.
2. GenServers poll API-Football on intervals; cache raw payloads in ETS.
3. Mapped events/stats/ratings broadcast via PubSub topics.
4. LiveView subscribes and updates assigns; components render diffed assigns; hooks update charts.
5. Players are added/removed via `PlayerSupervisor` when lineups change.

## UI Notes

- Tailwind + daisyUI: use `card`, `tabs`, `badge`, `progress`, `alert` for events.
- Heroicons for status (goal, card, sub, VAR).
- Keep JS minimal; all state in LiveView assigns; hooks only for charts.

## Next Steps

1. `mix phx.new momentix --live` and move code into `lib/momentix` and `lib/momentix_web`.
2. Add Finch to deps and configure in `application.ex`.
3. Implement `MatchSupervisor` and one GenServer end-to-end (e.g., `EventsServer`) with PubSub wiring.
4. Scaffold LiveView + components and wire sample data; integrate charts via hooks.
5. Add ETS cache + retry logic; exercise with a sandbox API-Football key.
