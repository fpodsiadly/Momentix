defmodule MomentixWeb.DashboardLive do
  use MomentixWeb, :live_view

  import MomentixWeb.DashboardComponents

  # FC Barcelona
  @default_team_id "529"
  @default_team_label "FC Barcelona"
  @default_match "demo"

  def mount(params, _session, socket) do
    team_id = normalize_team_id(params["team_id"])
    match_id = Map.get(params, "match_id", @default_match)

    socket =
      socket
      |> assign(:current_scope, nil)
      |> assign(:team_id, team_id)
      |> assign(:default_team_id, @default_team_id)
      |> assign(:default_team_label, @default_team_label)
      |> assign(:match_id, match_id)
      |> assign(:match_options, [])
      |> assign(:match_notice, nil)
      |> assign(:match_error, nil)
      |> assign(:match_topics, [])
      |> assign(:team_form, to_form(%{"team_id" => team_id, "match_id" => match_id}, as: :team))
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

  @impl true
  def handle_params(params, _uri, socket) do
    team_id = normalize_team_id(params["team_id"])
    requested_match_id = normalize_match_id(params["match_id"])

    {matches, match_notice, match_error} = load_matches(team_id)

    match_id =
      cond do
        requested_match_id ->
          requested_match_id

        matches != [] ->
          matches |> List.first() |> Map.get(:id, @default_match)

        true ->
          @default_match
      end

    socket =
      socket
      |> assign(:team_id, team_id)
      |> assign(:match_options, matches)
      |> assign(:match_notice, match_notice)
      |> assign(:match_error, match_error)
      |> assign(:team_form, to_form(%{"team_id" => team_id, "match_id" => match_id}, as: :team))

    {:noreply, attach_match(socket, match_id, team_id)}
  end

  @impl true
  def handle_event(
        "set_team",
        %{"team" => %{"team_id" => team_id, "match_id" => match_id}},
        socket
      ) do
    team_id = normalize_team_id(team_id)
    match_id = normalize_match_id(match_id)

    path =
      case match_id do
        nil ->
          ~p"/?#{%{team_id: team_id}}"

        _ ->
          ~p"/matches/#{match_id}?#{%{team_id: team_id}}"
      end

    {:noreply, push_patch(socket, to: path)}
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
      <div class="mx-auto max-w-6xl px-4 py-10 space-y-8">
        <div class="overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-r from-slate-900/80 via-slate-900/70 to-indigo-900/60 shadow-2xl shadow-indigo-500/10">
          <div class="flex flex-col gap-6 p-6 lg:flex-row lg:items-end lg:justify-between">
            <div class="space-y-2 text-white">
              <p class="text-xs uppercase tracking-[0.35em] text-white/60">Live tracker</p>
              <h1 class="text-3xl font-semibold">Match pulse</h1>
              <p class="text-sm text-white/70">
                Defaulting to {@default_team_label} (ID {@default_team_id}) when no team is provided.
              </p>
            </div>

            <.form
              for={@team_form}
              id="team-form"
              class="grid w-full gap-3 lg:max-w-xl"
              phx-submit="set_team"
            >
              <div class="grid gap-3 md:grid-cols-2">
                <.input
                  field={@team_form[:team_id]}
                  label="Team (API-Football ID)"
                  placeholder="529 for FC Barcelona"
                  class="input-bordered bg-white/10 text-white placeholder:text-white/60"
                />

                <.input
                  type="select"
                  field={@team_form[:match_id]}
                  label="Live match"
                  prompt="Auto-select live fixture"
                  options={match_options(@match_options)}
                  class="select-bordered bg-white/10 text-white"
                />
              </div>

              <div class="flex flex-wrap gap-3 md:justify-end">
                <button
                  type="submit"
                  class="inline-flex items-center justify-center gap-2 rounded-2xl bg-gradient-to-r from-indigo-400 to-indigo-600 px-4 py-3 text-sm font-semibold text-slate-900 shadow-lg shadow-indigo-500/40 transition hover:-translate-y-0.5 hover:shadow-xl focus:outline-none focus:ring-2 focus:ring-indigo-200"
                >
                  <.icon name="hero-play" class="h-4 w-4" />
                  <span>Update feed</span>
                </button>
              </div>
            </.form>
          </div>

          <div
            :if={@match_notice || @match_error}
            class="border-t border-white/10 bg-black/20 px-6 py-4"
          >
            <p :if={@match_notice} class="text-sm text-white/80">{@match_notice}</p>
            <p :if={@match_error} class="text-sm text-rose-200">{@match_error}</p>
          </div>
        </div>

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

  defp attach_match(socket, match_id, team_id) do
    current_match = socket.assigns[:match_id]
    subscribed? = socket.assigns[:match_topics] != []

    if current_match == match_id and subscribed? do
      socket
    else
      socket
      |> unsubscribe_from_topics()
      |> reset_match_state()
      |> assign(:match_id, match_id)
      |> subscribe_to_match(match_id, team_id, current_match)
    end
  end

  defp subscribe_to_match(socket, match_id, team_id, previous_match_id) do
    topics = match_topics(match_id)

    if connected?(socket) do
      Enum.each(topics, &Phoenix.PubSub.subscribe(Momentix.PubSub, &1))
      _ = Momentix.MatchSupervisor.start_match(match_id, team_id)
      maybe_stop_match(socket, previous_match_id, match_id)
    end

    assign(socket, :match_topics, topics)
  end

  defp unsubscribe_from_topics(%{assigns: %{match_topics: topics}} = socket) do
    if connected?(socket) do
      Enum.each(topics, &Phoenix.PubSub.unsubscribe(Momentix.PubSub, &1))
    end

    assign(socket, :match_topics, [])
  end

  defp match_topics(match_id) do
    for channel <- ~w(clock score stats events momentum players),
        do: "match:#{match_id}:#{channel}"
  end

  defp reset_match_state(socket) do
    socket
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
  end

  defp load_matches(team_id) do
    cond do
      team_id in [nil, ""] ->
        {[], "Using default team #{@default_team_label} (#{@default_team_id}).", nil}

      true ->
        case api_client().fetch_live_matches(team_id) do
          {:ok, matches} ->
            notice =
              case matches do
                [] ->
                  "No live fixtures for team #{team_id}. Falling back to demo data."

                [first | _] ->
                  "Following #{format_match_label(first)} (team #{team_id})."
              end

            {matches, notice, nil}

          {:error, reason} ->
            {[], nil, friendly_error(reason)}
        end
    end
  end

  defp match_options(matches) do
    Enum.map(matches, fn match ->
      {format_match_label(match), match.id}
    end)
  end

  defp format_match_label(%{home_team: home, away_team: away} = match) do
    [home || "Home", "vs", away || "Away", format_kickoff(match), match.status || "live"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp format_kickoff(%{date: nil}), do: ""

  defp format_kickoff(%{date: date}) do
    case DateTime.from_iso8601(date) do
      {:ok, dt, _offset} ->
        "• " <> Calendar.strftime(dt, "%H:%M UTC")

      _ ->
        ""
    end
  end

  defp friendly_error(:missing_api_key),
    do: "Missing API-Football key. Set API_FOOTBALL_KEY to see live data."

  defp friendly_error({:http_error, status}),
    do: "API-Football returned status #{status}. Showing demo data instead."

  defp friendly_error(reason), do: "Could not fetch data: #{inspect(reason)}"

  defp normalize_team_id(nil), do: @default_team_id

  defp normalize_team_id(team_id) do
    team_id = team_id |> to_string() |> String.trim()

    cond do
      team_id == "" ->
        @default_team_id

      String.match?(team_id, ~r/barca|barcelona/i) ->
        @default_team_id

      true ->
        team_id
    end
  end

  defp normalize_match_id(nil), do: nil

  defp normalize_match_id(match_id) do
    match_id = match_id |> to_string() |> String.trim()

    if match_id == "" do
      nil
    else
      match_id
    end
  end

  defp maybe_stop_match(_socket, prev, new) when is_nil(prev) or prev == new, do: :ok

  defp maybe_stop_match(socket, prev, _new) do
    if connected?(socket) do
      Momentix.MatchSupervisor.stop_match(prev)
    end
  end

  defp api_client do
    Application.get_env(:momentix, :api_client, Momentix.Api.Client)
  end
end
