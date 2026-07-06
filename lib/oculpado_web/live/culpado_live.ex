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

  attr :url, :string, required: true
  attr :text, :string, required: true

  defp share_bar(assigns) do
    enc_url = URI.encode_www_form(assigns.url)
    enc_text = URI.encode_www_form(assigns.text)
    enc_full = URI.encode_www_form(assigns.text <> " " <> assigns.url)

    assigns =
      assign(assigns,
        wa: "https://wa.me/?text=#{enc_full}",
        x: "https://twitter.com/intent/tweet?text=#{enc_text}&url=#{enc_url}",
        tg: "https://t.me/share/url?url=#{enc_url}&text=#{enc_text}",
        fb: "https://www.facebook.com/sharer/sharer.php?u=#{enc_url}"
      )

    ~H"""
    <div class="mt-5">
      <p class="text-xs uppercase tracking-wide text-white/40 mb-2">compartilhar</p>
      <div class="flex flex-wrap items-center justify-center gap-2">
        <button
          id="share-native"
          phx-hook="Share"
          data-url={@url}
          data-text={@text}
          type="button"
          class="share-btn"
        >
          <.share_icon name="link" /> <span class="btn-label">Compartilhar</span>
        </button>
        <a href={@wa} target="_blank" rel="noopener" class="share-btn" style="--sc:#25d366">
          <.share_icon name="whatsapp" /> WhatsApp
        </a>
        <a href={@x} target="_blank" rel="noopener" class="share-btn" style="--sc:#ffffff">
          <.share_icon name="x" /> Post
        </a>
        <a href={@tg} target="_blank" rel="noopener" class="share-btn" style="--sc:#229ed9">
          <.share_icon name="telegram" /> Telegram
        </a>
        <a href={@fb} target="_blank" rel="noopener" class="share-btn" style="--sc:#1877f2">
          <.share_icon name="facebook" /> Facebook
        </a>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true

  defp share_icon(%{name: "whatsapp"} = assigns) do
    ~H"""
    <svg class="share-ico" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.71.306 1.263.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.885-9.885 9.885M20.52 3.449C18.24 1.245 15.24 0 12.045 0 5.463 0 .104 5.334.101 11.892c0 2.096.549 4.14 1.595 5.945L0 24l6.335-1.652a12.062 12.062 0 005.71 1.454h.006c6.585 0 11.946-5.335 11.949-11.893a11.821 11.821 0 00-3.481-8.46z" />
    </svg>
    """
  end

  defp share_icon(%{name: "telegram"} = assigns) do
    ~H"""
    <svg class="share-ico" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z" />
    </svg>
    """
  end

  defp share_icon(%{name: "facebook"} = assigns) do
    ~H"""
    <svg class="share-ico" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z" />
    </svg>
    """
  end

  defp share_icon(%{name: "x"} = assigns) do
    ~H"""
    <svg class="share-ico" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
    </svg>
    """
  end

  defp share_icon(%{name: "link"} = assigns) do
    ~H"""
    <svg
      class="share-ico"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
    """
  end
end
