defmodule Oculpado.Votes do
  @moduledoc """
  Contagem de votos por partida, com leitura em memória (ETS) e persistência em SQLite.

  - Leitura / tempo real: tabela **ETS** com chave `{match_id, player_id}` => contagem.
    Incrementos são atômicos (`:ets.update_counter/4`), então vários usuários votam ao
    mesmo tempo sem travar a votação.
  - Durabilidade: cada voto também é gravado no **SQLite** (`Oculpado.Repo`), e no boot
    os totais são recarregados do banco para o ETS. Assim, deploys/restarts **não zeram**
    a votação (basta o arquivo do banco persistir, ex.: num Fly Volume).
  """

  use GenServer

  alias Oculpado.Repo

  @table :oculpado_votes

  # ----- API pública -----

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Tópico do PubSub de uma partida."
  def topic(match_id), do: "votes:#{match_id}"

  @doc "Assina as atualizações da votação de uma partida."
  def subscribe(match_id) do
    Phoenix.PubSub.subscribe(Oculpado.PubSub, topic(match_id))
  end

  @doc """
  Registra um voto para `player_id` na partida `match_id`.
  `delta` pode ser +1 (votar) ou -1 (tirar voto). ETS é atômico; o SQLite é atualizado
  logo em seguida com um upsert também atômico.
  """
  def vote(match_id, player_id, delta \\ 1) when delta in [1, -1] do
    key = {match_id, player_id}
    # +1: incremento simples. -1: decrementa com piso em 0 (threshold como mínimo).
    op = if delta == 1, do: {2, 1}, else: {2, -1, 0, 0}
    new_count = :ets.update_counter(@table, key, op, {key, 0})
    persist(match_id, player_id, new_count)
    broadcast(match_id, tally(match_id))
    :ok
  end

  @doc "Mapa `%{player_id => contagem}` com todos os candidatos de uma partida."
  def tally(match_id) do
    base = Map.new(Oculpado.Data.candidate_ids(match_id), &{&1, 0})

    # conta só os candidatos atuais: votos órfãos (ex.: opções de um palpite que virou
    # jogo de culpado, mantendo o mesmo match_id) são ignorados sem tocar no banco.
    @table
    |> :ets.match_object({{match_id, :_}, :_})
    |> Enum.reduce(base, fn {{_m, pid}, count}, acc ->
      if Map.has_key?(base, pid), do: Map.put(acc, pid, count), else: acc
    end)
  end

  @doc "Total de votos de uma partida."
  def total_votes(match_id) do
    tally(match_id) |> Map.values() |> Enum.sum()
  end

  # ----- GenServer -----

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    create_table!()
    load_from_db!()

    # garante entrada (zero) para todo candidato que ainda não estiver no ETS
    for m <- Oculpado.Data.matches(), id <- Enum.map(m.candidates, & &1.id) do
      :ets.insert_new(@table, {{m.id, id}, 0})
    end

    {:ok, %{}}
  end

  # ----- persistência (SQLite via Repo) -----

  defp create_table! do
    Repo.query!("""
    CREATE TABLE IF NOT EXISTS votes (
      match_id INTEGER NOT NULL,
      player_id INTEGER NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (match_id, player_id)
    )
    """)
  end

  defp load_from_db! do
    %{rows: rows} = Repo.query!("SELECT match_id, player_id, count FROM votes")

    for [match_id, player_id, count] <- rows do
      :ets.insert(@table, {{match_id, player_id}, count})
    end
  end

  # Grava o novo total (já calculado atomicamente no ETS) no SQLite.
  defp persist(match_id, player_id, count) do
    Repo.query!(
      """
      INSERT INTO votes (match_id, player_id, count)
      VALUES (?, ?, ?)
      ON CONFLICT(match_id, player_id) DO UPDATE SET count = excluded.count
      """,
      [match_id, player_id, count]
    )
  end

  defp broadcast(match_id, tally) do
    Phoenix.PubSub.broadcast(Oculpado.PubSub, topic(match_id), {:tally, match_id, tally})
  end
end
