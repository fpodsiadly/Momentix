defmodule Momentix.Cache do
  @moduledoc """
  Lightweight ETS cache with TTL support for API responses.
  """

  use GenServer

  @table :momentix_cache
  @default_ttl_ms 5_000
  @default_sweep_ms 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def put(key, value, ttl_ms \\ @default_ttl_ms) do
    GenServer.call(__MODULE__, {:put, key, value, ttl_ms})
  end

  def fetch(key) do
    case :ets.lookup(table_name(), key) do
      [{^key, value, expires_at}] ->
        if expired?(expires_at) do
          :ets.delete(table_name(), key)
          :miss
        else
          {:ok, value}
        end

      _ ->
        :miss
    end
  end

  @impl true
  def init(opts) do
    table = opts[:table] || @table
    create_table(table)

    state = %{table: table, sweep_ms: opts[:sweep_ms] || @default_sweep_ms}
    schedule_sweep(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl_ms}, _from, state) do
    expires_at = System.monotonic_time(:millisecond) + ttl_ms
    true = :ets.insert(state.table, {key, value, expires_at})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sweep, %{table: table} = state) do
    now = System.monotonic_time(:millisecond)
    match = {{:_, :_, :_}}

    :ets.select_delete(table, [{match, [{:<, {:element, 3, :"$_"}, now}], [true]}])
    schedule_sweep(state)
    {:noreply, state}
  end

  defp table_name, do: @table

  defp create_table(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  defp schedule_sweep(%{sweep_ms: nil}), do: :ok

  defp schedule_sweep(%{sweep_ms: sweep_ms}) do
    Process.send_after(self(), :sweep, sweep_ms)
  end

  defp expired?(ts), do: ts <= System.monotonic_time(:millisecond)
end
