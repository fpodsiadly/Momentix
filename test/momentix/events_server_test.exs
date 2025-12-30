defmodule Momentix.EventsServerTest do
  use ExUnit.Case, async: false

  alias Momentix.EventsServer
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

  test "broadcasts new events" do
    match_id = "m" <> Integer.to_string(System.unique_integer([:positive]))

    FakeApiClient.put_events([
      %{
        "id" => 1,
        "type" => "Goal",
        "detail" => "Normal Goal",
        "time" => %{"elapsed" => 12},
        "player" => %{"id" => 99, "name" => "Striker"},
        "team" => %{"id" => 10, "name" => "Home"}
      }
    ])

    Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:events")

    Phoenix.PubSub.broadcast(Momentix.PubSub, "match:#{match_id}:events", {:event, :ping})
    assert_receive {:event, :ping}

    assert {:ok, events} = FakeApiClient.fetch_events(match_id)
    assert length(events) == 1

    pid =
      start_supervised!({EventsServer, match_id: match_id, poll_ms: 10, client: FakeApiClient})

    state = :sys.get_state(pid)
    assert state.client == FakeApiClient

    seen = GenServer.call(pid, :poll_now)
    assert MapSet.size(seen) == 1

    assert_receive {:event, event}, 500
    assert event[:type] == :goal or event["type"] == "Goal"
    assert get_in(event, ["team", "id"]) == 10 or Map.get(event, :team_id) == "10"

    assert get_in(event, ["player", "name"]) == "Striker" or
             Map.get(event, :player_name) == "Striker"
  end
end
