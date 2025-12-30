defmodule MomentixWeb.PageControllerTest do
  use MomentixWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "Live"
    assert body =~ "Events"
    assert body =~ "Players"
  end
end
