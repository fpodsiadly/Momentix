defmodule Momentix.ScoreServerTest do
  use ExUnit.Case, async: false

  alias Momentix.ScoreServer
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

  test "broadcasts official score with team names" do
    match_id = "m" <> Integer.to_string(System.unique_integer([:positive]))

    FakeApiClient.put_score(%{
      home: 2,
      away: 1,
      home_name: "Lions",
      away_name: "Tigers",
      home_id: "11",
      away_id: "22"
    })

    Phoenix.PubSub.subscribe(Momentix.PubSub, "match:#{match_id}:score")

    Phoenix.PubSub.broadcast(Momentix.PubSub, "match:#{match_id}:score", {:score, :ping})
    assert_receive {:score, :ping}

    assert {:ok, %{home: 2, away: 1}} = FakeApiClient.fetch_score(match_id)

    pid = start_supervised!({ScoreServer, match_id: match_id, poll_ms: 10, client: FakeApiClient})

    state = :sys.get_state(pid)
    assert state.client == FakeApiClient

    score = GenServer.call(pid, :poll_now)
    assert score.home == 2

    assert_receive {:score, score}, 500
    assert score.home == 2
    assert score.away == 1
    assert score.home_name == "Lions"
    assert score.away_name == "Tigers"
  end
end
