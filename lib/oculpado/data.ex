defmodule Oculpado.Data do
  @moduledoc """
  Carrega TODAS as partidas a partir dos JSONs em `priv/data`.

  Os dados são lidos e normalizados uma única vez no boot (via `load/0`) e ficam
  guardados em `:persistent_term`, servindo todas as requisições sem tocar em disco
  nem em banco.

  Suporta dois formatos de arquivo:

    * completo — com `home`/`away` (cada um com `team` + `players`);
    * apenas perdedor — com `match.loser` + `loser_team.players`.

  Em ambos, os candidatos a "culpado" são os jogadores do time que **perdeu**.
  """

  @pt_key {__MODULE__, :matches}

  # IDs de time do Sofascore por nome — usados como fallback quando o JSON
  # (formato "só perdedor") não traz o id do time vencedor.
  @team_ids %{
    "Brazil" => 4748,
    "Norway" => 4475,
    "Canada" => 4752,
    "Morocco" => 4778,
    "Paraguay" => 4789,
    "France" => 4481
  }

  @doc "Mapa nome do time => id do SofaScore (fallback para o formato \"só perdedor\")."
  def known_team_ids, do: @team_ids

  @doc "Lê e normaliza todas as partidas do disco e guarda em memória. Chamado no boot."
  def load do
    matches =
      :oculpado
      |> Application.app_dir("priv/data")
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(&(&1 |> File.read!() |> Jason.decode!()))
      |> Enum.map(&build_match/1)
      |> Enum.sort_by(& &1.kickoff)

    :persistent_term.put(@pt_key, %{
      list: matches,
      by_slug: Map.new(matches, &{&1.slug, &1})
    })

    :ok
  end

  @doc "Lista de todas as partidas (com candidatos já normalizados)."
  def matches, do: store().list

  @doc "Busca uma partida pelo slug. Retorna nil se não existir."
  def match(slug), do: Map.get(store().by_slug, slug)

  @doc "Candidatos (jogadores do time perdedor) de uma partida."
  def candidates(slug) do
    case match(slug) do
      nil -> []
      m -> m.candidates
    end
  end

  @doc """
  IDs dos candidatos de uma partida. Aceita o slug (string) ou o id do jogo (integer,
  usado pelo `Oculpado.Votes`).
  """
  def candidate_ids(slug) when is_binary(slug), do: candidates(slug) |> Enum.map(& &1.id)

  def candidate_ids(match_id) when is_integer(match_id) do
    case Enum.find(matches(), &(&1.id == match_id)) do
      nil -> []
      m -> Enum.map(m.candidates, & &1.id)
    end
  end

  @doc "Mapa id => candidato de uma partida."
  def candidates_by_id(slug), do: Map.new(candidates(slug), &{&1.id, &1})

  defp store do
    :persistent_term.get(@pt_key, nil) || (load() && :persistent_term.get(@pt_key))
  end

  # ---- construção / normalização ----

  defp build_match(%{"match" => %{"mode" => "prediction"}} = json), do: build_prediction(json)
  defp build_match(json), do: build_culprit(json)

  # Jogo já encerrado: vote no culpado (jogadores + técnico do time perdedor).
  defp build_culprit(json) do
    match = json["match"]
    home = match["home"]
    away = match["away"]
    {home_goals, away_goals} = parse_score(match["score"])

    loser = match["loser"] || if(home_goals <= away_goals, do: home, else: away)

    players = loser_players(json, loser, home)
    {home_id, away_id} = team_ids(json, loser, home)
    # completa ids faltantes (ex.: vencedor no formato "só perdedor"): primeiro pelos
    # ids gravados no próprio JSON, depois pelo mapa por nome do time.
    home_id = home_id || match["home_id"] || @team_ids[home]
    away_id = away_id || match["away_id"] || @team_ids[away]
    loser_id = if loser == home, do: home_id, else: away_id

    %{
      id: match["id"],
      mode: :culprit,
      slug: build_slug(match, home, away),
      home: home,
      away: away,
      score: match["score"],
      home_goals: home_goals,
      away_goals: away_goals,
      penalties: match["penalties"],
      decided_on_penalties: match["decided_on_penalties"] || false,
      featured: match["featured"] || false,
      loser: loser,
      home_logo: team_logo(home_id),
      away_logo: team_logo(away_id),
      loser_logo: match["loser_logo"] || team_logo(loser_id),
      kickoff: match["startTimestamp"] || "",
      candidates:
        players
        |> Enum.map(&normalize/1)
        |> sort_candidates()
        |> maybe_add_coach(match["loser_coach"])
        |> maybe_add_referee(match["loser_referee"])
        |> maybe_add_extras(match["extra_culprits"])
    }
  end

  # Jogo que ainda não aconteceu: palpite de quem vence (mandante / empate / visitante).
  # As três opções reaproveitam o mesmo sistema de votos (id da opção = id do time; empate = 0).
  defp build_prediction(json) do
    match = json["match"]
    home = match["home"]
    away = match["away"]
    home_id = match["home_id"] || @team_ids[home]
    away_id = match["away_id"] || @team_ids[away]

    options = [
      %{id: home_id, kind: :home, label: home, logo: team_logo(home_id), votes: 0},
      %{id: 0, kind: :draw, label: "Empate", logo: nil, votes: 0},
      %{id: away_id, kind: :away, label: away, logo: team_logo(away_id), votes: 0}
    ]

    %{
      id: match["id"],
      mode: :prediction,
      slug: build_slug(match, home, away),
      home: home,
      away: away,
      score: nil,
      loser: nil,
      featured: false,
      home_logo: team_logo(home_id),
      away_logo: team_logo(away_id),
      loser_logo: nil,
      kickoff: match["startTimestamp"] || "",
      candidates: options
    }
  end

  # O técnico também pode ser culpado — entra como candidato no fim da lista.
  defp maybe_add_coach(candidates, %{"id" => id, "name" => name} = c) when is_integer(id) do
    coach = %{
      id: id,
      name: name,
      short_name: name,
      number: nil,
      position: "Técnico",
      position_code: "C",
      starter: false,
      minutes: 0,
      captain: false,
      rating: nil,
      goals: nil,
      coach: true,
      referee: false,
      photo:
        c["photo_override"] || Oculpado.Assets.local_path(:manager, id) ||
          "https://api.sofascore.com/api/v1/manager/#{id}/image"
    }

    candidates ++ [coach]
  end

  defp maybe_add_coach(candidates, _), do: candidates

  # O árbitro também pode ser o culpado — entra como candidato no fim da lista.
  defp maybe_add_referee(candidates, %{"id" => id, "name" => name} = r) when is_integer(id) do
    referee = %{
      id: id,
      name: name,
      short_name: name,
      number: nil,
      position: "Árbitro",
      position_code: "R",
      starter: false,
      minutes: 0,
      captain: false,
      rating: nil,
      goals: nil,
      coach: false,
      referee: true,
      photo:
        r["photo_override"] || Oculpado.Assets.local_path(:referee, id) ||
          "https://api.sofascore.com/api/v1/referee/#{id}/image"
    }

    candidates ++ [referee]
  end

  defp maybe_add_referee(candidates, _), do: candidates

  # Culpados de zoeira (VAR, a bola, o gramado…) — entram no fim da lista.
  defp maybe_add_extras(candidates, extras) when is_list(extras) do
    extra =
      Enum.map(extras, fn e ->
        %{
          id: e["id"],
          name: e["name"],
          short_name: e["name"],
          number: nil,
          position: e["position"],
          position_code: nil,
          starter: false,
          minutes: 0,
          captain: false,
          rating: nil,
          goals: nil,
          coach: false,
          referee: false,
          badge: e["badge"],
          photo: e["photo"]
        }
      end)

    candidates ++ extra
  end

  defp maybe_add_extras(candidates, _), do: candidates

  # Ids dos times (home, away). No formato "perdedor" só temos o id do time que perdeu.
  defp team_ids(json, loser, home) do
    cond do
      is_map(json["home"]) and is_map(json["away"]) ->
        {get_in(json, ["home", "team", "id"]), get_in(json, ["away", "team", "id"])}

      is_map(json["loser_team"]) ->
        loser_id = json["loser_team"]["id"]
        if loser == home, do: {loser_id, nil}, else: {nil, loser_id}

      true ->
        {nil, nil}
    end
  end

  defp team_logo(nil), do: nil

  defp team_logo(id) do
    # Prioriza o arquivo local (SofaScore bloqueia hotlink no Fly). Cai na URL
    # remota só quando a imagem ainda não foi baixada (rode Oculpado.Assets.fetch_all/0).
    Oculpado.Assets.local_path(:team, id) || "https://api.sofascore.com/api/v1/team/#{id}/image"
  end

  defp loser_players(json, loser, home) do
    cond do
      is_map(json["loser_team"]) ->
        json["loser_team"]["players"] || []

      true ->
        side = if loser == home, do: json["home"], else: json["away"]
        (side && side["players"]) || []
    end
  end

  defp sort_candidates(players) do
    Enum.sort_by(players, fn p -> {(p.starter && 0) || 1, -p.minutes} end)
  end

  defp parse_score(nil), do: {0, 0}

  defp parse_score(score) do
    case String.split(score, "-") do
      [h, a] -> {to_int(h), to_int(a)}
      _ -> {0, 0}
    end
  end

  defp to_int(s), do: s |> String.trim() |> String.to_integer()

  defp build_slug(match, home, away) do
    match["slug"] || slugify("#{home}-#{away}")
  end

  defp slugify(str) do
    str
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/\s+/, "-")
  end

  defp normalize(p) do
    %{
      id: p["id"],
      name: p["name"],
      short_name: p["shortName"],
      number: p["jerseyNumber"],
      position: p["position_pt"],
      position_code: p["position"],
      starter: p["starter"],
      minutes: p["minutesPlayed"] || 0,
      captain: p["captain"] || false,
      rating: p["rating"],
      goals: p["goals"],
      coach: false,
      referee: false,
      photo: player_photo(p)
    }
  end

  # Prioriza a foto local baixada; cai na URL do SofaScore quando ainda não existe.
  defp player_photo(p) do
    p["photo_override"] || Oculpado.Assets.local_path(:player, p["id"]) || p["photo"]
  end
end
