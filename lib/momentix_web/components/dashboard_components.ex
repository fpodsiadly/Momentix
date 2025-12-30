defmodule MomentixWeb.DashboardComponents do
  @moduledoc """
  UI components for the realtime dashboard.
  """

  use Phoenix.Component

  import MomentixWeb.CoreComponents

  attr :id, :string, required: true
  attr :match_id, :string, default: nil
  attr :home_name, :string, default: "Home"
  attr :away_name, :string, default: "Away"
  attr :score, :map, default: %{home: 0, away: 0}
  attr :clock, :string, default: "00:00"

  def scoreboard(assigns) do
    ~H"""
    <div
      id={@id}
      class="h-full rounded-2xl border border-white/10 bg-slate-900/70 p-5 shadow-xl shadow-indigo-500/10 backdrop-blur"
    >
      <div class="flex items-center justify-between text-[11px] uppercase tracking-[0.28em] text-white/60">
        <div class="inline-flex items-center gap-2 rounded-full bg-white/5 px-3 py-1 font-semibold text-emerald-200">
          <.icon name="hero-bolt" class="h-4 w-4" />
          <span>Live</span>
        </div>
        <span class="font-mono text-xs text-white/70">Match {@match_id}</span>
      </div>

      <div class="mt-6 grid grid-cols-3 items-center text-center text-white">
        <div class="space-y-1">
          <p class="text-sm text-white/60">Home</p>
          <p class="text-lg font-semibold leading-tight truncate">{@home_name}</p>
        </div>
        <div class="flex flex-col items-center gap-2">
          <div class="text-5xl font-black tracking-tight">{@score.home} - {@score.away}</div>
          <div class="rounded-full bg-white/10 px-3 py-1 text-xs font-mono text-white/70">
            {@clock}
          </div>
        </div>
        <div class="space-y-1">
          <p class="text-sm text-white/60">Away</p>
          <p class="text-lg font-semibold leading-tight truncate">{@away_name}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :series, :list, default: []

  def momentum_panel(assigns) do
    ~H"""
    <div
      id={@id}
      class="h-full rounded-2xl border border-white/10 bg-slate-900/70 p-5 shadow-xl shadow-indigo-500/10 backdrop-blur"
    >
      <div class="flex items-center justify-between">
        <div class="inline-flex items-center gap-2 rounded-full bg-amber-500/15 px-3 py-1 text-sm font-semibold text-amber-200">
          <.icon name="hero-fire" class="h-5 w-5" />
          <span>Momentum</span>
        </div>
        <span class="rounded-full border border-white/15 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-white/70">
          Live
        </span>
      </div>
      <div
        id="momentum-chart"
        phx-hook="MomentumChart"
        data-series={Jason.encode!(@series)}
        class="mt-4 flex min-h-[200px] items-center justify-center rounded-xl border border-dashed border-white/15 bg-white/5 text-sm text-white/60"
      >
        <span class="font-mono">Waiting for data...</span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :possession, :map, default: %{home: 50, away: 50}

  def possession_panel(assigns) do
    ~H"""
    <div
      id={@id}
      class="h-full rounded-2xl border border-white/10 bg-slate-900/70 p-5 shadow-xl shadow-indigo-500/10 backdrop-blur"
    >
      <div class="flex items-center justify-between">
        <div class="inline-flex items-center gap-2 rounded-full bg-cyan-500/15 px-3 py-1 text-sm font-semibold text-cyan-100">
          <.icon name="hero-chart-pie" class="h-5 w-5" />
          <span>Possession</span>
        </div>
        <span class="rounded-full border border-white/15 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-white/70">
          Live
        </span>
      </div>
      <div
        id="possession-chart"
        phx-hook="PossessionChart"
        data-home={@possession.home}
        data-away={@possession.away}
        class="mt-4 flex min-h-[200px] items-center justify-center rounded-xl border border-dashed border-white/15 bg-white/5 text-sm text-white/70"
      >
        <span class="font-mono">Home {@possession.home}% vs Away {@possession.away}%</span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :stats, :map, default: %{}

  def stat_cards(assigns) do
    stats = summarize_stats(assigns.stats)
    assigns = assign(assigns, :stat_list, stats)

    ~H"""
    <div id={@id} class="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
      <div
        :for={stat <- @stat_list}
        class="rounded-2xl border border-white/10 bg-slate-900/70 p-4 shadow-lg shadow-indigo-500/10 transition hover:-translate-y-0.5 hover:border-indigo-400/40"
      >
        <div class="flex items-center gap-2 text-sm text-white/60">
          <.icon name={stat.icon} class="h-4 w-4" />
          <span>{stat.label}</span>
        </div>
        <div class="mt-3 text-2xl font-semibold text-white">{stat.home} - {stat.away}</div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :events, :list, default: []

  def event_feed(assigns) do
    ~H"""
    <div
      id={@id}
      class="lg:col-span-2 rounded-2xl border border-white/10 bg-slate-900/70 p-5 shadow-xl shadow-indigo-500/10 backdrop-blur"
    >
      <div class="flex items-center justify-between">
        <div class="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-sm font-semibold text-white">
          <.icon name="hero-list-bullet" class="h-5 w-5" />
          <span>Events</span>
        </div>
        <span class="rounded-full border border-white/15 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-white/70">
          Live
        </span>
      </div>
      <div class="mt-4 max-h-[360px] space-y-2 overflow-auto pr-1">
        <div :if={@events == []} class="text-sm text-white/60">No events yet.</div>
        <div
          :for={event <- @events}
          id={"evt-#{event[:id]}"}
          class="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-white/90"
        >
          <div class="flex items-center gap-2 text-sm">
            <.icon name={icon_for_event(event)} class="h-4 w-4 text-indigo-300" />
            <span>{event[:type] || event["type"]}</span>
            <span class="text-white/60">{event[:detail] || event["detail"]}</span>
          </div>
          <div class="text-xs font-mono text-white/60">{event[:at] || event["at"] || 0}'</div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :players, :map, default: %{}

  def player_list(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-2xl border border-white/10 bg-slate-900/70 p-5 shadow-xl shadow-indigo-500/10 backdrop-blur"
    >
      <div class="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-sm font-semibold text-white">
        <.icon name="hero-users" class="h-5 w-5" />
        <span>Players</span>
      </div>
      <div class="mt-4 max-h-[360px] space-y-2 overflow-auto pr-1">
        <div :if={map_size(@players) == 0} class="text-sm text-white/60">No player data yet.</div>
        <div
          :for={{_id, player} <- @players}
          class="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-white/90"
        >
          <div class="flex items-center gap-2 text-sm">
            <span class="rounded-full border border-white/30 bg-white/10 px-2 py-1 text-xs font-semibold">
              #{player.number || ""}
            </span>
            <span>{player.name}</span>
          </div>
          <div class="text-xs font-mono text-white/70">{player.rating || "-"}</div>
        </div>
      </div>
    </div>
    """
  end

  defp summarize_stats(stats) when map_size(stats) == 0 do
    [
      %{label: "Possession", home: 50, away: 50, icon: "hero-chart-pie"},
      %{label: "Shots", home: 0, away: 0, icon: "hero-bolt"},
      %{label: "xG", home: 0.0, away: 0.0, icon: "hero-sparkles"},
      %{label: "Corners", home: 0, away: 0, icon: "hero-flag"}
    ]
  end

  defp summarize_stats(stats) do
    [home, away] = Map.values(stats) |> Enum.take(2)

    [
      %{
        label: "Possession",
        home: value(home, "Ball Possession"),
        away: value(away, "Ball Possession"),
        icon: "hero-chart-pie"
      },
      %{
        label: "Shots",
        home: value(home, "Total Shots"),
        away: value(away, "Total Shots"),
        icon: "hero-bolt"
      },
      %{
        label: "xG",
        home: value(home, "Expected Goals"),
        away: value(away, "Expected Goals"),
        icon: "hero-sparkles"
      },
      %{
        label: "Corners",
        home: value(home, "Corner Kicks"),
        away: value(away, "Corner Kicks"),
        icon: "hero-flag"
      }
    ]
  end

  defp value(map, key) do
    val = map[key]

    cond do
      is_number(val) ->
        val

      is_binary(val) ->
        val
        |> String.replace("%", "")
        |> Float.parse()
        |> case do
          {parsed, _} -> parsed
          :error -> 0
        end

      true ->
        0
    end
  end

  defp icon_for_event(%{type: :goal}), do: "hero-trophy"
  defp icon_for_event(%{type: :own_goal}), do: "hero-arrow-uturn-down"
  defp icon_for_event(%{type: :yellow}), do: "hero-rectangle-stack"
  defp icon_for_event(%{type: :second_yellow}), do: "hero-rectangle-stack"
  defp icon_for_event(%{type: :red}), do: "hero-rectangle-stack"
  defp icon_for_event(%{type: :card}), do: "hero-rectangle-stack"
  defp icon_for_event(%{type: :substitution}), do: "hero-arrow-path"
  defp icon_for_event(_), do: "hero-dot"
end
