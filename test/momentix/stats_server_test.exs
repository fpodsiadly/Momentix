defmodule Momentix.StatsServerTest do
  use ExUnit.Case, async: false

  alias Momentix.PlayerSupervisor
  alias Momentix.StatsServer
  alias Momentix.TestSupport.FakeApiClient

  setup do
    FakeApiClient.reset()
    Application.put_env(:momentix, :api_client, FakeApiClient)

    on_exit(fn ->
      Application.delete_env(:momentix, :api_client)
      FakeApiClient.reset()
    end)

    :ok
  end

  test "broadcasts stats, momentum, and lineup" do
    match_id = "m" <> Integer.to_string(System.unique_integer([:positive]))

    FakeApiClient.put_stats(%{
      "Home" => %{"Ball Possession" => 60, "Total Shots" => 10},
      "Away" => %{"Ball Possession" => 40, "Total Shots" => 5}
    })

    FakeApiClient.put_players([
      %{id: "p1", name: "Alpha", number: 9, rating: 7.5},
      %{id: "p2", name: "Beta", number: 4, rating: 6.0}
    ])

    Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:stats")
    Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:momentum")
    Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:players")

    start_supervised!({PlayerSupervisor, match_id: match_id})
    pid = start_supervised!({StatsServer, match_id: match_id, poll_ms: 10, client: FakeApiClient})

    state = :sys.get_state(pid)
    assert state.client == FakeApiClient

    assert {:ok, %{stats: fake_stats}} = FakeApiClient.fetch_stats(match_id)
    assert Map.has_key?(fake_stats, "Home")

    stats_reply = GenServer.call(pid, :poll_now)
    assert Map.has_key?(stats_reply, "Home")

    assert_receive {:stats, %{stats: stats}}, 500
    assert %{"Ball Possession" => 60} = Map.fetch!(stats, "Home") |> Map.take(["Ball Possession"])

    assert_receive {:momentum, momentum}, 500
    assert Enum.any?(momentum, &(&1.team == "Home"))

    assert_receive {:players, players}, 500
    assert Enum.any?(players, &(&1.id == "p1"))
  end
end
