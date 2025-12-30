defmodule Momentix.PlayerSupervisor do
  @moduledoc """
  Dynamic supervisor for per-player processes inside a match.
  """

  use DynamicSupervisor

  alias Momentix.Match.Names
  alias Momentix.PlayerServer

  def start_link(opts) do
    match_id = Keyword.fetch!(opts, :match_id)

    DynamicSupervisor.start_link(__MODULE__, %{match_id: match_id},
      name: Names.via(match_id, __MODULE__)
    )
  end

  @impl true
  def init(_state), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_player(match_id, player_id) do
    spec = {PlayerServer, match_id: match_id, player_id: player_id}

    Names.via(match_id, __MODULE__)
    |> lookup_supervisor()
    |> case do
      {:ok, sup} -> DynamicSupervisor.start_child(sup, spec)
      error -> error
    end
  end

  def start_lineup(match_id, player_ids) when is_list(player_ids) do
    Enum.each(player_ids, &start_player(match_id, &1))
    :ok
  end

  defp lookup_supervisor(via) do
    case GenServer.whereis(via) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end
end
