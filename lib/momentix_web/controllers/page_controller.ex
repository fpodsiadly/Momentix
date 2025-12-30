defmodule MomentixWeb.PageController do
  use MomentixWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
