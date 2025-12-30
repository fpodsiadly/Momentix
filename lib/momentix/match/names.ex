defmodule Momentix.Match.Names do
  @moduledoc """
  Helper functions for consistent Registry names for match processes.
  """

  @registry Momentix.MatchRegistry

  def registry, do: @registry

  def via(match_id, module) do
    {:via, Registry, {@registry, {match_id, module}}}
  end
end
