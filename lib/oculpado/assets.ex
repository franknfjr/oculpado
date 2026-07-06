defmodule Oculpado.Assets do
  @moduledoc """
  Baixa e hospeda **localmente** os escudos dos times e as fotos dos jogadores.

  O SofaScore bloqueia hotlink por IP/Referer (no Fly as imagens simplesmente não
  renderizam). Então baixamos uma única vez a partir de uma máquina não bloqueada
  (local) e passamos a servir os arquivos do próprio app, em
  `priv/static/images/{teams,players}/{id}.{ext}` — que são versionados e vão junto
  no deploy.

  Fluxo: adicionou/atualizou JSONs em `priv/data`? Rode localmente:

      mix run -e "Oculpado.Assets.fetch_all()"

  Depois faça o commit dos arquivos gerados em `priv/static/images` e o deploy.

  O download valida os *magic bytes* de cada imagem (png/webp/jpg) — nada de HTML de
  erro ou arquivo corrompido entra no repositório.
  """

  require Logger

  @sofa "https://api.sofascore.com/api/v1"
  @ua "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"

  @doc """
  Baixa todas as imagens referenciadas pelos JSONs de `priv/data`.

  Idempotente: pula o que já existe (passe `force: true` para rebaixar tudo).
  Retorna um resumo `%{ok: n, skip: n, fail: [ids...]}`.
  """
  def fetch_all(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    %{teams: teams, players: players} = collect_refs()

    Logger.info("[assets] #{MapSet.size(teams)} times e #{MapSet.size(players)} jogadores")

    results =
      Enum.map(teams, &{:team, &1, fetch(:team, &1, force)}) ++
        Enum.map(players, &{:player, &1, fetch(:player, &1, force)})

    summarize(results)
  end

  @doc "Diretório base dos assets locais (`priv/static/images`)."
  def images_dir, do: Application.app_dir(:oculpado, "priv/static/images")

  @doc """
  Caminho web (`/images/...`) da imagem local já baixada, ou `nil` se não existir.

  Usado pelo `Oculpado.Data` para trocar a URL do SofaScore pelo arquivo local.
  """
  def local_path(kind, id) when kind in [:team, :player] and not is_nil(id) do
    dir = Path.join(images_dir(), plural(kind))

    Enum.find_value([".webp", ".png", ".jpg"], fn ext ->
      if File.exists?(Path.join(dir, "#{id}#{ext}")), do: "/images/#{plural(kind)}/#{id}#{ext}"
    end)
  end

  def local_path(_kind, _id), do: nil

  # ---- interno ----

  defp collect_refs do
    :oculpado
    |> Application.app_dir("priv/data")
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&(&1 |> File.read!() |> Jason.decode!()))
    |> Enum.reduce(%{teams: MapSet.new(), players: MapSet.new()}, fn json, acc ->
      %{
        teams: MapSet.union(acc.teams, team_ids(json)),
        players: MapSet.union(acc.players, player_ids(json))
      }
    end)
  end

  defp team_ids(json) do
    match = json["match"] || %{}
    by_name = Oculpado.Data.known_team_ids()

    [
      get_in(json, ["home", "team", "id"]),
      get_in(json, ["away", "team", "id"]),
      get_in(json, ["loser_team", "id"]),
      # nos JSONs "só perdedor" o vencedor só aparece pelo nome — resolve pelo mapa
      by_name[match["home"]],
      by_name[match["away"]]
    ]
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp player_ids(json) do
    sides = [json["home"], json["away"], json["loser_team"]]

    sides
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&(&1["players"] || []))
    |> Enum.map(& &1["id"])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp fetch(kind, id, force) do
    if not force and local_path(kind, id) do
      :skip
    else
      case download("#{@sofa}/#{kind}/#{id}/image") do
        {:ok, ext, body} ->
          dir = Path.join(images_dir(), plural(kind))
          File.mkdir_p!(dir)
          File.write!(Path.join(dir, "#{id}#{ext}"), body)
          :ok

        {:error, reason} ->
          Logger.warning("[assets] #{kind} #{id} falhou: #{inspect(reason)}")
          :error
      end
    end
  end

  defp download(url) do
    case System.cmd("curl", ["-sfL", "-A", @ua, url], into: "") do
      {body, 0} ->
        case magic_ext(body) do
          nil -> {:error, :not_an_image}
          ext -> {:ok, ext, body}
        end

      {_, code} ->
        {:error, {:curl_exit, code}}
    end
  end

  # valida magic bytes e devolve a extensão correta
  defp magic_ext(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: ".png"
  defp magic_ext(<<0xFF, 0xD8, 0xFF, _::binary>>), do: ".jpg"
  defp magic_ext(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: ".webp"
  defp magic_ext(_), do: nil

  defp plural(:team), do: "teams"
  defp plural(:player), do: "players"

  defp summarize(results) do
    ok = Enum.count(results, fn {_, _, r} -> r == :ok end)
    skip = Enum.count(results, fn {_, _, r} -> r == :skip end)
    fail = for {kind, id, :error} <- results, do: {kind, id}

    Logger.info("[assets] ok=#{ok} skip=#{skip} fail=#{length(fail)}")
    %{ok: ok, skip: skip, fail: fail}
  end
end
