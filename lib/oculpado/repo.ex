defmodule Oculpado.Repo do
  use Ecto.Repo,
    otp_app: :oculpado,
    adapter: Ecto.Adapters.SQLite3
end
