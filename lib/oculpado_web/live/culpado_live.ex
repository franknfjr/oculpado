defmodule OculpadoWeb.CulpadoLive do
  use OculpadoWeb, :live_view

  alias Oculpado.{Data, Votes}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Data.match(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Partida não encontrada") |> push_navigate(to: ~p"/")}

      match ->
        if connected?(socket), do: Votes.subscribe(match.id)

        art = article(match.loser)
        page_url = url(~p"/match/#{match.slug}")

        share_text =
          "Quem foi o culpado pela eliminação #{art} #{match.loser}? " <>
            "#{match.home} #{match.score} #{match.away}. Vote você também:"

        socket =
          socket
          |> assign(:page_title, "O Culpado · #{match.loser}")
          |> assign(:match, match)
          |> assign(:candidates_by_id, Map.new(match.candidates, &{&1.id, &1}))
          |> assign(:selected, MapSet.new())
          |> assign(:page_url, page_url)
          |> assign(:share_text, share_text)
          |> assign(
            :og_title,
            "O Culpado #{art} #{match.loser} — #{match.home} #{match.score} #{match.away}"
          )
          |> assign(
            :og_description,
            "Vote em quem foi o culpado pela eliminação #{art} #{match.loser}. Resultado ao vivo."
          )
          |> assign(:og_image, absolute_image(match.loser_logo))
          |> assign_tally(Votes.tally(match.id))

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)
    match = socket.assigns.match
    selected = socket.assigns.selected

    {selected, delta} =
      if MapSet.member?(selected, id) do
        {MapSet.delete(selected, id), -1}
      else
        {MapSet.put(selected, id), +1}
      end

    Votes.vote(match.id, id, delta)

    socket =
      socket
      |> assign(:selected, selected)
      |> assign_tally(Votes.tally(match.id))
      |> push_event("sync_selected", %{key: store_key(match), ids: MapSet.to_list(selected)})

    {:noreply, socket}
  end

  # Restaura a seleção visual salva no navegador (não altera a contagem global).
  def handle_event("restore", %{"ids" => ids}, socket) do
    valid = MapSet.new(Data.candidate_ids(socket.assigns.match.slug))

    selected =
      ids |> Enum.map(&to_int/1) |> Enum.filter(&MapSet.member?(valid, &1)) |> MapSet.new()

    {:noreply, assign(socket, :selected, selected)}
  end

  @impl true
  def handle_info({:tally, match_id, tally}, socket) do
    if match_id == socket.assigns.match.id do
      {:noreply, assign_tally(socket, tally)}
    else
      {:noreply, socket}
    end
  end

  # ---- helpers ----

  defp store_key(match), do: "oculpado:selected:#{match.slug}"

  defp assign_tally(socket, tally) do
    by_id = socket.assigns.candidates_by_id
    total = tally |> Map.values() |> Enum.sum()
    max = tally |> Map.values() |> Enum.max(fn -> 0 end)

    ranked =
      by_id
      |> Map.values()
      |> Enum.map(fn p -> Map.put(p, :votes, Map.get(tally, p.id, 0)) end)
      # mais para menos votado; desempate pelo número da camisa (crescente)
      |> Enum.sort_by(fn p -> {-p.votes, jersey(p.number)} end)
      |> Enum.with_index(1)
      |> Enum.map(fn {p, pos} -> Map.put(p, :rank, pos) end)

    socket
    |> assign(:ranked, ranked)
    |> assign(:total, total)
    |> assign(:max, max)
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  # número da camisa como inteiro para ordenar (999 se ausente/estranho)
  defp jersey(nil), do: 999

  defp jersey(n) do
    case Integer.parse(to_string(n)) do
      {i, _} -> i
      :error -> 999
    end
  end

  defp pct(_votes, 0), do: 0
  defp pct(votes, total), do: round(votes / total * 100)

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="culpado-bg"
      id={"culpado-#{@match.slug}"}
      phx-hook="VoterSync"
      data-store-key={store_key(@match)}
    >
      <div class="mx-auto max-w-2xl px-4 py-8 sm:py-12">
        <.link
          navigate={~p"/"}
          class="inline-flex items-center gap-1 text-white/50 hover:text-white/80 text-sm mb-4"
        >
          ← todas as partidas
        </.link>

        <header class="text-center mb-8">
          <div class="pill inline-flex items-center gap-1.5 mb-3">
            <img
              :if={@match.home_logo}
              src={@match.home_logo}
              alt={@match.home}
              class="w-4 h-4 object-contain"
            />
            {@match.home} {@match.score} {@match.away}
            <img
              :if={@match.away_logo}
              src={@match.away_logo}
              alt={@match.away}
              class="w-4 h-4 object-contain"
            />
          </div>

          <img
            :if={@match.loser_logo}
            src={@match.loser_logo}
            alt={@match.loser}
            class="w-20 h-20 mx-auto mb-2 object-contain drop-shadow"
          />

          <h1 class="text-4xl sm:text-6xl font-black tracking-tight">
            O <span style="color: var(--br-yellow)">CULPADO</span>
          </h1>
          <p class="mt-3 text-white/70">
            Quem foi o culpado pela eliminação {article(@match.loser)} <strong>{@match.loser}</strong>?
            <br class="hidden sm:block" /> Toque em <strong>quantos jogadores</strong>
            quiser. A lista atualiza em tempo real.
          </p>

          <div class="mt-5 inline-flex items-center gap-2 rounded-full bg-white/5 px-4 py-2">
            <span class="text-2xl font-black" style="color: var(--br-yellow)">{@total}</span>
            <span class="text-white/60 text-sm">votos registrados</span>
          </div>

          <.share_bar url={@page_url} text={@share_text} />
        </header>

        <ul id="ranking" phx-hook="FlipList" class="space-y-3">
          <li
            :for={p <- @ranked}
            id={"player-#{p.id}"}
            class={[
              "culpa-card rise cursor-pointer select-none px-3 py-3 sm:px-4",
              MapSet.member?(@selected, p.id) && "is-selected"
            ]}
            phx-click="toggle"
            phx-value-id={p.id}
          >
            <div class="sweep"></div>
            <div class="flex items-center gap-3">
              <div class={["rank-badge shrink-0", "rank-#{p.rank}"]}>{p.rank}</div>

              <img
                src={p.photo}
                alt={p.name}
                loading="lazy"
                class="w-12 h-12 rounded-full object-cover bg-white/10 shrink-0"
              />

              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <span class="font-bold truncate">{p.name}</span>
                  <span :if={p.captain} class="pill">C</span>
                  <span :if={p.coach} class="pill" style="color: var(--br-yellow)">TÉCNICO</span>
                  <span :if={p.referee} class="pill" style="color: var(--br-yellow)">ÁRBITRO</span>
                  <span class="vote-check text-lg" style="color: var(--br-yellow)">✓</span>
                </div>
                <div class="flex items-center gap-2 text-xs text-white/60 mt-0.5">
                  <span :if={p.number}>#{p.number}</span>
                  <span :if={p.number}>·</span>
                  <span>{p.position}</span>
                  <span :if={p.goals && p.goals > 0} class="pill">⚽ {p.goals}</span>
                </div>

                <div class="mt-2 h-2 w-full rounded-full bg-white/10 overflow-hidden">
                  <div class="culpa-bar" style={"width: #{pct(p.votes, (@max == 0 && 1) || @max)}%"}>
                  </div>
                </div>
              </div>

              <div class="text-right shrink-0 w-14">
                <div
                  id={"count-#{p.id}"}
                  phx-hook="Bump"
                  data-count={p.votes}
                  class="text-2xl font-black leading-none"
                >
                  {p.votes}
                </div>
                <div class="text-[10px] uppercase tracking-wide text-white/50">
                  {pct(p.votes, @total)}%
                </div>
              </div>
            </div>
          </li>
        </ul>

        <.github_footer />
      </div>
    </div>
    """
  end

  defp article(loser) do
    if String.ends_with?(loser, "a"), do: "da", else: "do"
  end

  # og:image precisa de URL absoluta. Escudos locais viram "/images/..."; aqui
  # prefixamos o host. URLs remotas (fallback) já são absolutas — passam direto.
  defp absolute_image(nil), do: nil
  defp absolute_image("http" <> _ = url), do: url
  defp absolute_image("/" <> _ = path), do: OculpadoWeb.Endpoint.url() <> path
end
