defmodule MomentixWeb.DashboardLiveTest do
  use MomentixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Momentix.TestSupport.FakeApiClient

  setup %{conn: conn} do
    FakeApiClient.reset()
    Application.put_env(:momentix, :api_client, FakeApiClient)

    on_exit(fn ->
      Application.delete_env(:momentix, :api_client)
      FakeApiClient.reset()
    end)

    {:ok, conn: conn}
  end

  test "renders updates from PubSub", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    Phoenix.PubSub.broadcast(
      Momentix.PubSub,
      "match:demo:score",
      {:score, %{home: 1, away: 0, home_name: "Lions", away_name: "Tigers"}}
    )

    Phoenix.PubSub.broadcast(
      Momentix.PubSub,
      "match:demo:stats",
      {:stats,
       %{
         stats: %{"Home" => %{"Ball Possession" => 60}, "Away" => %{"Ball Possession" => 40}},
         momentum: [%{team: "Home", value: 60}]
       }}
    )

    Phoenix.PubSub.broadcast(
      Momentix.PubSub,
      "match:demo:events",
      {:event, %{id: 1, type: :goal, detail: "Normal Goal", at: 12}}
    )

    Phoenix.PubSub.broadcast(
      Momentix.PubSub,
      "match:demo:players",
      {:players, [%{id: "p1", name: "Alpha", number: 9, rating: 7.5}]}
    )

    render(view)

    assert has_element?(view, "#scoreboard", "Lions")
    assert has_element?(view, "#event-feed", "Normal Goal")
    assert has_element?(view, "#player-list", "Alpha")
    assert has_element?(view, "#possession", "60%")
  end
end
