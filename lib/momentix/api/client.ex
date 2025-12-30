defmodule Momentix.Api.Client do
  @moduledoc """
  Thin wrapper around API-Football using Req with ETS caching and retry/backoff.
  """

  require Logger

  alias Momentix.Cache

  @default_base "https://v3.football.api-sports.io"
  @default_ttl_ms 5_000

  def enabled?, do: api_key() not in [nil, ""]

  def fetch_live_matches(team_id, opts \\ []) do
    fetch_cached({:live_matches, team_id}, opts, fn ->
      get("/fixtures", %{"live" => "all", "team" => team_id})
      |> parse_response(&map_matches/1)
    end)
  end

  def fetch_events(match_id, opts \\ []) do
    fetch_cached({:events, match_id}, opts, fn ->
      get("/fixtures/events", %{"fixture" => match_id})
      |> parse_response(&map_events/1)
    end)
  end

  def fetch_stats(match_id, opts \\ []) do
    fetch_cached({:stats, match_id}, opts, fn ->
      get("/fixtures/statistics", %{"fixture" => match_id})
      |> parse_response(&map_stats/1)
    end)
  end

  def fetch_score(match_id, opts \\ []) do
    fetch_cached({:score, match_id}, opts, fn ->
      get("/fixtures", %{"id" => match_id})
      |> parse_response(&map_score/1)
    end)
  end

  def fetch_players(match_id, opts \\ []) do
    fetch_cached({:players, match_id}, opts, fn ->
      get("/fixtures/players", %{"fixture" => match_id})
      |> parse_response(&map_players/1)
    end)
  end

  defp fetch_cached(cache_key, opts, fun) do
    ttl = Keyword.get(opts, :ttl_ms, @default_ttl_ms)

    case Cache.fetch(cache_key) do
      {:ok, cached} ->
        {:ok, cached}

      :miss ->
        case fun.() do
          {:ok, value} = ok ->
            Cache.put(cache_key, value, ttl)
            ok

          error ->
            error
        end
    end
  end

  defp get(path, params) do
    if enabled?() do
      req()
      |> Req.get(url: path, params: params)
    else
      {:error, :missing_api_key}
    end
  end

  defp req do
    base_url = api_base()
    host_header = api_host(base_url)

    Req.new(
      base_url: base_url,
      headers: [
        {"x-rapidapi-key", api_key()},
        {"x-rapidapi-host", host_header},
        {"accept", "application/json"}
      ],
      finch: Momentix.Finch,
      retry: :transient,
      retry_delay: &retry_backoff/1,
      max_retries: 3
    )
  end

  defp api_config, do: Application.get_env(:momentix, :api_football, [])
  defp api_key, do: Keyword.get(api_config(), :api_key) || System.get_env("API_FOOTBALL_KEY")
  defp api_base, do: Keyword.get(api_config(), :base_url, @default_base)

  defp api_host(base_url) do
    case URI.parse(base_url) do
      %URI{host: nil} -> "v3.football.api-sports.io"
      %URI{host: host} -> host
    end
  end

  defp retry_backoff(attempt) do
    trunc(:math.pow(2, attempt) * 150 + :rand.uniform(150))
  end

  defp parse_response({:ok, %Req.Response{status: status, body: %{"response" => body}}}, mapper)
       when status in 200..299 do
    {:ok, mapper.(body)}
  end

  defp parse_response({:ok, %Req.Response{status: status, body: body}}, _mapper) do
    Logger.warning("api_football unexpected status #{status}: #{inspect(body)}")
    {:error, {:http_error, status}}
  end

  defp parse_response({:error, reason}, _mapper), do: {:error, reason}

  defp map_matches(list) when is_list(list) do
    Enum.map(list, fn match ->
      fixture = match["fixture"] || %{}
      teams = match["teams"] || %{}

      %{
        id: to_string(fixture["id"] || fixture["fixture_id"] || unique_id()),
        status: fixture["status"] && fixture["status"]["short"],
        date: fixture["date"],
        home_team: team_name(teams["home"]),
        away_team: team_name(teams["away"])
      }
    end)
  end

  defp map_events(list) when is_list(list) do
    Enum.map(list, fn ev ->
      time = ev["time"] || %{}
      player = ev["player"] || %{}
      assist = ev["assist"] || %{}
      team = ev["team"] || %{}

      %{
        id: to_string(ev["id"] || unique_id()),
        type: normalize_event_type(ev["type"], ev["detail"]),
        at: time["elapsed"] || 0,
        extra: time["extra"],
        player_id: maybe_string(player["id"]) || maybe_string(player["name"]),
        player_name: player["name"],
        assist_id: maybe_string(assist["id"]),
        assist_name: assist["name"],
        team_id: maybe_string(team["id"]),
        team_name: team["name"],
        detail: ev["detail"],
        comments: ev["comments"]
      }
    end)
  end

  defp map_stats(list) when is_list(list) do
    list
    |> Enum.reduce(%{}, fn stat, acc ->
      team = stat["team"] || %{}
      stats = stat["statistics"] || []

      key = team_key(team)
      Map.put(acc, key, normalize_stats(stats))
    end)
    |> then(fn stats_map ->
      %{
        type: :stat_update,
        stats: stats_map,
        momentum: momentum_from_stats(stats_map)
      }
    end)
  end

  defp map_score(list) when is_list(list) do
    first = List.first(list) || %{}
    fixture = first["fixture"] || %{}
    teams = first["teams"] || %{}
    goals = first["goals"] || %{}

    home = teams["home"] || %{}
    away = teams["away"] || %{}

    %{
      home: goals["home"] || 0,
      away: goals["away"] || 0,
      home_id: maybe_string(home["id"]),
      away_id: maybe_string(away["id"]),
      home_name: home["name"],
      away_name: away["name"],
      status: fixture["status"] && fixture["status"]["short"]
    }
  end

  defp map_players(list) when is_list(list) do
    list
    |> Enum.flat_map(fn team_block -> team_block["players"] || [] end)
    |> Enum.map(fn player ->
      info = player["player"] || %{}
      statistics = (player["statistics"] || []) |> List.first() || %{}
      rating = statistics["games"] && statistics["games"]["rating"]
      team = statistics["team"] || %{}

      %{
        id: to_string(info["id"] || unique_id()),
        name: info["name"],
        number: info["number"],
        position: statistics["games"] && statistics["games"]["position"],
        rating: parse_rating(rating),
        minutes: statistics["games"] && statistics["games"]["minutes"],
        team_id: maybe_string(team["id"]),
        team_name: team["name"]
      }
    end)
  end

  defp team_key(%{"id" => id}) when not is_nil(id), do: to_string(id)
  defp team_key(%{"name" => name}), do: name
  defp team_key(_), do: unique_id()

  defp team_name(nil), do: nil
  defp team_name(team), do: team["name"] || team["id"]

  defp normalize_event_type("Goal", detail), do: (detail == "Own Goal" && :own_goal) || :goal

  defp normalize_event_type("Card", detail) when detail in ["Yellow Card", "Second Yellow"] do
    (detail == "Second Yellow" && :second_yellow) || :yellow
  end

  defp normalize_event_type("Card", _detail), do: :red
  defp normalize_event_type("subst", _), do: :substitution

  defp normalize_event_type(type, _detail) when is_binary(type),
    do: String.to_atom(String.downcase(type))

  defp normalize_event_type(_, _), do: :unknown

  defp normalize_stats(stats) do
    Enum.reduce(stats, %{}, fn stat, acc ->
      key = stat["type"]
      value = stat["value"]
      Map.put(acc, key, normalize_number(value))
    end)
  end

  defp momentum_from_stats(stats_map) do
    if map_size(stats_map) == 0 do
      []
    else
      Enum.map(stats_map, fn {team, stats} ->
        shot_total = stats["Total Shots"] || 0
        possession = stats["Ball Possession"] || 0
        %{team: team, value: momentum_value(shot_total, possession)}
      end)
    end
  end

  defp momentum_value(shot_total, possession) do
    shots = normalize_number(shot_total)
    poss = normalize_number(possession)
    shots * 0.6 + poss * 0.4
  end

  defp parse_rating(nil), do: nil

  defp parse_rating(rating) when is_binary(rating) do
    case Float.parse(rating) do
      {val, _} -> Float.round(val, 2)
      :error -> nil
    end
  end

  defp parse_rating(rating) when is_number(rating), do: Float.round(rating * 1.0, 2)
  defp parse_rating(_), do: nil

  defp normalize_number(val) when is_integer(val), do: val * 1.0
  defp normalize_number(val) when is_float(val), do: val

  defp normalize_number(val) when is_binary(val) do
    val
    |> String.replace("%", "")
    |> Float.parse()
    |> case do
      {parsed, _} -> parsed
      :error -> 0.0
    end
  end

  defp normalize_number(_), do: 0.0

  defp maybe_string(nil), do: nil
  defp maybe_string(val) when is_binary(val), do: val
  defp maybe_string(val), do: to_string(val)

  defp unique_id do
    System.unique_integer([:positive, :monotonic])
  end
end
