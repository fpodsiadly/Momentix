defmodule Momentix.Repo do
  use Ecto.Repo,
    otp_app: :momentix,
    adapter: Ecto.Adapters.Postgres
end
