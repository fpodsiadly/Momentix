defmodule MomentixWeb.DashboardLive do
  use MomentixWeb, :live_view

  import MomentixWeb.DashboardComponents

  @default_match "demo"

  def mount(params, _session, socket) do
    match_id = Map.get(params, "match_id", @default_match)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:clock")
      Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:score")
      Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:stats")
      Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:events")
      Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:momentum")
      Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:players")

      _ = Momentix.MatchSupervisor.start_match(match_id, params["team_id"])
    end

    socket =
      socket
      |> assign(:current_scope, nil)
      |> assign(:match_id, match_id)
      |> assign(:clock_ms, 0)
      |> assign(:phase, :pre)
      |> assign(:score, %{home: 0, away: 0})
      |> assign(:home_name, "Home")
      |> assign(:away_name, "Away")
      |> assign(:stats, %{})
      |> assign(:events, [])
      |> assign(:players, %{})
      |> assign(:possession, %{home: 50, away: 50})
      |> assign(:momentum_series, default_momentum())

    {:ok, socket}
  end

  def handle_info({:clock_tick, elapsed_ms, phase}, socket) do
    {:noreply, assign(socket, clock_ms: elapsed_ms, phase: phase)}
  end

  def handle_info({:score, score}, socket) do
    socket =
      socket
      |> assign(:score, Map.take(score, [:home, :away]))
      |> assign(:home_name, score[:home_name] || socket.assigns.home_name)
      |> assign(:away_name, score[:away_name] || socket.assigns.away_name)

    {:noreply, socket}
  end

  def handle_info({:stats, %{stats: stats, momentum: momentum}}, socket) do
    possession = derive_possession(stats)

    socket =
      socket
      |> assign(:stats, stats)
      |> assign(:possession, possession)
      |> push_event("possession:update", possession)
      |> push_event("momentum:update", %{series: encode_momentum(momentum)})

    {:noreply, socket}
  end

  def handle_info({:momentum, momentum}, socket) do
    {:noreply, push_event(socket, "momentum:update", %{series: encode_momentum(momentum)})}
  end

  def handle_info({:event, event}, socket) do
    events = [event | socket.assigns.events] |> Enum.take(20)
    {:noreply, assign(socket, events: events)}
  end

  def handle_info({:player, player}, socket) do
    players = Map.put(socket.assigns.players, player.id, player)
    {:noreply, assign(socket, players: players)}
  end

  def handle_info({:players, players}, socket) do
    players_map =
      players
      |> Enum.map(fn player -> {player.id, player} end)
      |> Map.new()

    {:noreply, assign(socket, players: players_map)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl px-4 py-8 space-y-6">
        <div class="grid gap-4 md:grid-cols-3">
          <.scoreboard
            id="scoreboard"
            match_id={@match_id}
            home_name={@home_name}
            away_name={@away_name}
            score={@score}
            clock={format_clock(@clock_ms)}
          />
          <.momentum_panel id="momentum" series={@momentum_series} />
          <.possession_panel id="possession" possession={@possession} />
        </div>

        <.stat_cards id="stat-cards" stats={@stats} />

        <div class="grid gap-4 lg:grid-cols-3">
          <.event_feed id="event-feed" events={@events} />
          <.player_list id="player-list" players={@players} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_clock(ms) when is_integer(ms) do
    total_seconds = div(ms, 1_000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, seconds]) |> IO.iodata_to_binary()
  end

  defp default_momentum do
    [
      %{team: "Home", value: 50},
      %{team: "Away", value: 50}
    ]
  end

  defp derive_possession(stats) when map_size(stats) == 0 do
    %{home: 50, away: 50}
  end

  defp derive_possession(stats) do
    [home, away] = Map.values(stats) |> Enum.take(2)
    home_val = normalize_stat(home["Ball Possession"]) || 0
    away_val = normalize_stat(away["Ball Possession"]) || 0
    %{home: home_val, away: away_val}
  end

  defp normalize_stat(val) when is_integer(val), do: val
  defp normalize_stat(val) when is_float(val), do: val

  defp normalize_stat(val) when is_binary(val) do
    val |> String.replace("%", "") |> String.to_integer()
  rescue
    _ -> 0
  end

  defp normalize_stat(_), do: 0

  defp encode_momentum(momentum) do
    Enum.map(momentum, fn %{team: team, value: value} -> %{name: team, data: [value]} end)
  end
end
