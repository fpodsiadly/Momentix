# Momentix

Realtime football match dashboard built with Phoenix LiveView. Focused on fast, fault-tolerant ingestion of API-Football data from API-Football and clean UI updates via PubSub.

## System Overview

- Elixir OTP app with a per-match supervision tree.
- Processes per match: `MatchClockServer`, `ScoreServer`, `StatsServer`, `EventsServer`, `PlayerSupervisor` (dynamic), `PlayerServer` (per player).
- Data fetchers use Finch + Req + ETS cache + retry/backoff with short TTLs.
- Phoenix PubSub distributes updates; LiveView subscribes and renders.
- UI: Tailwind components, LiveView hooks for momentum/possession, Heroicons.

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
- `Momentix.Api.Client` – Finch/Req wrapper with auth header, retry/backoff, rate-limit protection, field normalization for API-Football events/stats/score/players.
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

  - Subscribes to all match topics on mount; starts per-match tree via `MatchSupervisor.start_match/2`.
  - Tracks clock, score (with team names), stats, events, players, momentum series, possession.
  - Uses `push_event/3` for chart updates (`momentum:update`, `possession:update`).

- Components (see `lib/momentix_web/components/dashboard_components.ex`)

  - Scoreboard, momentum, possession, stat cards, event feed, player list (Heroicons used via `<.icon>`).

- JS hooks (see `assets/js/app.js`)
  - `MomentumChart` and `PossessionChart` render live textual summaries from pushed events.

## API Client and Caching

- Configure Finch pool `:api_football` with TLS and timeouts.
- `Client.fetch_live_matches(team_id)`, `fetch_events(match_id)`, `fetch_stats(match_id)`, `fetch_players(match_id)`, `fetch_score(match_id)`.
- ETS cache keys: `{:events, match_id}`, `{:stats, match_id}`, `{:players, match_id}` with short TTL (5–10s) to soften rate limits.
- Use exponential backoff on HTTP 429/5xx; jittered retries.
- Map API-Football payloads into typed maps before broadcasting.
- Set environment variables (loaded in `config/runtime.exs`):
  - `API_FOOTBALL_KEY` – required API key
  - `API_FOOTBALL_BASE_URL` – optional, defaults to `https://v3.football.api-sports.io`

## Data Flow

1. `MatchSupervisor.start_match(match_id, team_id)` starts `Match.Tree`.
2. GenServers poll API-Football on intervals; cache raw payloads in ETS.
3. Mapped events/stats/ratings broadcast via PubSub topics.
4. LiveView subscribes and updates assigns; components render diffed assigns; hooks update charts.
5. Players are added/removed via `PlayerSupervisor` when lineups change.

## UI Notes

- Tailwind components with badges/cards; Heroicons for status; charts driven by LiveView pushes.
- Keep JS minimal; all state in LiveView assigns; hooks only for chart text summaries.
