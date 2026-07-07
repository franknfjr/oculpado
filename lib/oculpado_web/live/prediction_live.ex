defmodule OculpadoWeb.PredictionLive do
  @moduledoc """
  Modo pré-jogo: palpite de quem vence (mandante / empate / visitante) antes da bola
  rolar. Reaproveita o mesmo sistema de votos em tempo real do "culpado".

  Escolha única: cada torcedor tem um voto; trocar de opção move o voto. A escolha fica
  salva no navegador (localStorage) via hook `VoterSync`.
  """
  use OculpadoWeb, :live_view

  alias Oculpado.{Data, Votes}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Data.match(slug) do
      %{mode: :prediction} = match ->
        if connected?(socket), do: Votes.subscribe(match.id)

        page_url = url(~p"/prediction/#{match.slug}")

        share_text =
          "Quem vence? #{match.home} x #{match.away}. Faça seu palpite antes do jogo:"

        socket =
          socket
          |> assign(:page_title, "Palpite · #{match.home} x #{match.away}")
          |> assign(:match, match)
          |> assign(:selected, nil)
          |> assign(:page_url, page_url)
          |> assign(:share_text, share_text)
          |> assign(:og_title, "Palpite: #{match.home} x #{match.away} — quem vence?")
          |> assign(
            :og_description,
            "Faça seu palpite de quem vence #{match.home} x #{match.away}."
          )
          |> assign(:og_image, absolute_image(match.home_logo))
          |> assign_tally(Votes.tally(match.id))

        {:ok, socket}

      _ ->
        {:ok, socket |> put_flash(:error, "Palpite não encontrado") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("pick", %{"id" => id}, socket) do
    id = to_int(id)
    prev = socket.assigns.selected
    match = socket.assigns.match

    selected =
      cond do
        prev == id ->
          # clicou de novo na mesma opção: tira o voto
          Votes.vote(match.id, id, -1)
          nil

        true ->
          # move o voto da opção anterior (se houver) para a nova
          if prev, do: Votes.vote(match.id, prev, -1)
          Votes.vote(match.id, id, 1)
          id
      end

    socket =
      socket
      |> assign(:selected, selected)
      |> assign_tally(Votes.tally(match.id))
      |> push_event("sync_selected", %{key: store_key(match), ids: (selected && [selected]) || []})

    {:noreply, socket}
  end

  # Restaura a escolha salva no navegador (não altera a contagem global).
  def handle_event("restore", %{"ids" => ids}, socket) do
    valid = MapSet.new(Enum.map(socket.assigns.match.candidates, & &1.id))
    selected = ids |> Enum.map(&to_int/1) |> Enum.find(&MapSet.member?(valid, &1))
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

  defp store_key(match), do: "oculpado:prediction:#{match.slug}"

  defp assign_tally(socket, tally) do
    options =
      Enum.map(socket.assigns.match.candidates, fn o ->
        Map.put(o, :votes, Map.get(tally, o.id, 0))
      end)

    total = options |> Enum.map(& &1.votes) |> Enum.sum()
    leader = options |> Enum.max_by(& &1.votes, fn -> nil end)

    socket
    |> assign(:options, options)
    |> assign(:total, total)
    |> assign(:leader_id, total > 0 && leader && leader.id)
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  defp pct(_votes, 0), do: 0
  defp pct(votes, total), do: round(votes / total * 100)

  # og:image precisa de URL absoluta.
  defp absolute_image(nil), do: nil
  defp absolute_image("http" <> _ = url), do: url
  defp absolute_image("/" <> _ = path), do: OculpadoWeb.Endpoint.url() <> path

  # Horário do jogo em Brasília (UTC-3).
  defp kickoff_brt(""), do: nil

  defp kickoff_brt(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} ->
        dt
        |> DateTime.add(-3 * 3600, :second)
        |> Calendar.strftime("%d/%m às %Hh%M")

      _ ->
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="culpado-bg"
      id={"palpite-#{@match.slug}"}
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
          <div class="pill inline-flex items-center gap-1.5 mb-3">PALPITE</div>

          <div class="flex items-center justify-center gap-3 sm:gap-5 mb-2">
            <div class="flex flex-col items-center gap-1">
              <img
                :if={@match.home_logo}
                src={@match.home_logo}
                alt={@match.home}
                class="w-16 h-16 object-contain"
              />
              <span class="text-sm text-white/80">{@match.home}</span>
            </div>
            <span class="text-2xl font-black text-white/40">x</span>
            <div class="flex flex-col items-center gap-1">
              <img
                :if={@match.away_logo}
                src={@match.away_logo}
                alt={@match.away}
                class="w-16 h-16 object-contain"
              />
              <span class="text-sm text-white/80">{@match.away}</span>
            </div>
          </div>

          <h1 class="text-4xl sm:text-6xl font-black tracking-tight mt-4">
            QUEM <span style="color: var(--br-yellow)">VENCE?</span>
          </h1>
          <p :if={kickoff_brt(@match.kickoff)} class="mt-2 text-white/60 text-sm">
            {kickoff_brt(@match.kickoff)} (horário de Brasília)
          </p>
          <p class="mt-3 text-white/70">
            Faça seu palpite antes da bola rolar. Toque numa opção — pode trocar até o apito inicial.
          </p>

          <div class="mt-5 inline-flex items-center gap-2 rounded-full bg-white/5 px-4 py-2">
            <span class="text-2xl font-black" style="color: var(--br-yellow)">{@total}</span>
            <span class="text-white/60 text-sm">palpites</span>
          </div>

          <.share_bar url={@page_url} text={@share_text} />
        </header>

        <ul class="space-y-3">
          <li
            :for={o <- @options}
            class={[
              "culpa-card rise cursor-pointer select-none px-4 py-4",
              @selected == o.id && "is-selected"
            ]}
            phx-click="pick"
            phx-value-id={o.id}
          >
            <div class="flex items-center gap-3">
              <img
                :if={o.logo}
                src={o.logo}
                alt={o.label}
                class="w-10 h-10 object-contain shrink-0"
              />
              <div
                :if={o.kind == :draw}
                class="w-10 h-10 shrink-0 flex items-center justify-center text-2xl"
              >
                🤝
              </div>

              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <span class="font-bold truncate">{o.label}</span>
                  <span :if={@leader_id == o.id} class="pill" style="color: var(--br-yellow)">
                    na frente
                  </span>
                  <span
                    :if={@selected == o.id}
                    class="vote-check text-lg"
                    style="color: var(--br-yellow)"
                  >
                    ✓ seu palpite
                  </span>
                </div>
                <div class="mt-2 h-2 w-full rounded-full bg-white/10 overflow-hidden">
                  <div
                    class="culpa-bar"
                    style={"width: #{pct(o.votes, (@total == 0 && 1) || @total)}%"}
                  >
                  </div>
                </div>
              </div>

              <div class="text-right shrink-0 w-14">
                <div class="text-2xl font-black leading-none">{pct(o.votes, @total)}%</div>
                <div class="text-[10px] uppercase tracking-wide text-white/50">{o.votes}</div>
              </div>
            </div>
          </li>
        </ul>

        <.github_footer />
      </div>
    </div>
    """
  end
end
