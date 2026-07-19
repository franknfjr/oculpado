defmodule OculpadoWeb.MatchesLive do
  use OculpadoWeb, :live_view

  alias Oculpado.{Data, Votes}

  @impl true
  def mount(_params, _session, socket) do
    matches = Data.matches()

    if connected?(socket) do
      for m <- matches, do: Votes.subscribe(m.id)
    end

    {predictions, culprits} = Enum.split_with(matches, &(&1.mode == :prediction))
    {featured, culprits} = Enum.split_with(culprits, & &1.featured)

    {:ok,
     socket
     |> assign(:page_title, "O Culpado")
     |> assign(:matches, matches)
     |> assign(:predictions, predictions)
     |> assign(:featured, featured)
     |> assign(:culprits, culprits)
     |> assign_totals()}
  end

  @impl true
  def handle_info({:tally, _match_id, _tally}, socket) do
    {:noreply, assign_totals(socket)}
  end

  defp assign_totals(socket) do
    totals = Map.new(socket.assigns.matches, &{&1.id, Votes.total_votes(&1.id)})
    assign(socket, :totals, totals)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="culpado-bg">
      <div class="mx-auto max-w-2xl px-4 py-10 sm:py-16">
        <header class="text-center mb-10">
          <h1 class="text-5xl sm:text-7xl font-black tracking-tight">
            O <span style="color: var(--br-yellow)">CULPADO</span>
          </h1>
          <p class="mt-3 text-white/70">
            Dê seu palpite nos jogos que vêm aí e vote no culpado dos que já acabaram.
          </p>
        </header>

        <section :if={@featured != []} class="mb-10">
          <li :for={m <- @featured} class="list-none">
            <.link navigate={~p"/match/#{m.slug}"} class="block">
              <div class="featured-card rise px-5 py-6 sm:px-6 sm:py-7">
                <div class="featured-shine"></div>
                <div class="flex items-center gap-2 text-xs font-black uppercase tracking-widest mb-3">
                  <span class="featured-badge">🏆 A FINAL — e deu zebra</span>
                </div>
                <div class="flex items-center justify-between gap-4">
                  <div class="min-w-0 flex items-center gap-3">
                    <img
                      :if={m.loser_logo}
                      src={m.loser_logo}
                      alt={m.loser}
                      class="w-14 h-14 object-contain shrink-0 drop-shadow"
                    />
                    <div class="min-w-0">
                      <div class="text-2xl sm:text-3xl font-black leading-tight">
                        Argentina perdeu a <span style="color: var(--br-yellow)">FINAL</span>
                      </div>
                      <div class="mt-1 text-sm sm:text-base font-bold flex items-center gap-2 flex-wrap">
                        <img
                          :if={m.home_logo}
                          src={m.home_logo}
                          alt={m.home}
                          class="w-5 h-5 object-contain"
                        />
                        {m.home}
                        <span style="color: var(--br-yellow)">{m.score}</span>
                        {m.away}
                        <img
                          :if={m.away_logo}
                          src={m.away_logo}
                          alt={m.away}
                          class="w-5 h-5 object-contain"
                        />
                        <span :if={m.decided_on_penalties} class="text-xs font-normal text-white/60">
                          pên. {m.penalties}
                        </span>
                      </div>
                      <div class="mt-1 text-sm text-white/70 italic">🇧🇷 Decime qué se siente…</div>
                    </div>
                  </div>
                  <div class="text-right shrink-0">
                    <div class="text-3xl font-black" style="color: var(--br-yellow)">
                      {Map.get(@totals, m.id, 0)}
                    </div>
                    <div class="text-[10px] uppercase tracking-wide text-white/60">votos</div>
                  </div>
                </div>
                <div class="mt-4">
                  <span class="pill featured-cta">apontar o culpado da taça →</span>
                </div>
              </div>
            </.link>
          </li>
        </section>

        <section :if={@predictions != []} class="mb-10">
          <h2 class="text-sm uppercase tracking-widest text-white/60 mb-3 flex items-center gap-2">
            <span style="color: var(--br-yellow)">●</span> Palpites — quem vence?
          </h2>
          <ul class="space-y-4">
            <li :for={m <- @predictions}>
              <.link navigate={~p"/prediction/#{m.slug}"} class="block">
                <div class="culpa-card rise px-4 py-4 sm:px-5 sm:py-5">
                  <div class="flex items-center justify-between gap-4">
                    <div class="min-w-0 flex items-center gap-3">
                      <div class="flex items-center gap-1 shrink-0">
                        <img
                          :if={m.home_logo}
                          src={m.home_logo}
                          alt={m.home}
                          class="w-9 h-9 object-contain"
                        />
                        <span class="text-white/40 font-black">x</span>
                        <img
                          :if={m.away_logo}
                          src={m.away_logo}
                          alt={m.away}
                          class="w-9 h-9 object-contain"
                        />
                      </div>
                      <div class="min-w-0">
                        <div class="text-xs uppercase tracking-wide text-white/50 mb-1">
                          Palpite • quem vence?
                        </div>
                        <div class="text-lg sm:text-2xl font-black truncate">
                          {m.home} <span class="text-white/40">x</span> {m.away}
                        </div>
                      </div>
                    </div>
                    <div class="text-right shrink-0">
                      <div class="text-2xl font-black" style="color: var(--br-yellow)">
                        {Map.get(@totals, m.id, 0)}
                      </div>
                      <div class="text-[10px] uppercase tracking-wide text-white/50">palpites</div>
                    </div>
                  </div>
                  <div class="mt-3 text-sm text-white/60 flex items-center gap-2">
                    <span class="pill">quem vence →</span>
                    <span
                      :if={m.kickoff != ""}
                      id={"cd-#{m.id}"}
                      class="pill countdown"
                      phx-hook="Countdown"
                      phx-update="ignore"
                      data-kickoff={m.kickoff}
                    >
                    </span>
                  </div>
                </div>
              </.link>
            </li>
          </ul>
        </section>

        <section :if={@culprits != []}>
          <h2 class="text-sm uppercase tracking-widest text-white/60 mb-3 flex items-center gap-2">
            Jogos encerrados — quem é o culpado?
          </h2>
          <ul class="space-y-4">
            <li :for={m <- @culprits}>
              <.link navigate={~p"/match/#{m.slug}"} class="block">
                <div class="culpa-card rise px-4 py-4 sm:px-5 sm:py-5">
                  <div class="flex items-center justify-between gap-4">
                    <div class="min-w-0 flex items-center gap-3">
                      <img
                        :if={m.loser_logo}
                        src={m.loser_logo}
                        alt={m.loser}
                        class="w-11 h-11 object-contain shrink-0"
                      />
                      <div class="min-w-0">
                        <div class="text-xs uppercase tracking-wide text-white/50 mb-1">
                          Culpado {article(m.loser)} <span class="text-white/80">{m.loser}</span>
                        </div>
                        <div class="text-lg sm:text-2xl font-black truncate flex items-center gap-2">
                          <img
                            :if={m.home_logo}
                            src={m.home_logo}
                            alt={m.home}
                            class="w-5 h-5 object-contain"
                          />
                          {m.home}
                          <span style="color: var(--br-yellow)">{m.score}</span>
                          {m.away}
                          <img
                            :if={m.away_logo}
                            src={m.away_logo}
                            alt={m.away}
                            class="w-5 h-5 object-contain"
                          />
                          <span
                            :if={m.decided_on_penalties}
                            class="text-xs font-normal text-white/50"
                          >
                            pên. {m.penalties}
                          </span>
                        </div>
                      </div>
                    </div>
                    <div class="text-right shrink-0">
                      <div class="text-2xl font-black" style="color: var(--br-yellow)">
                        {Map.get(@totals, m.id, 0)}
                      </div>
                      <div class="text-[10px] uppercase tracking-wide text-white/50">votos</div>
                    </div>
                  </div>
                  <div class="mt-3 text-sm text-white/60 flex items-center gap-2">
                    <span class="pill">votar →</span>
                  </div>
                </div>
              </.link>
            </li>
          </ul>
        </section>

        <.github_footer />
      </div>
    </div>
    """
  end

  defp article(loser) do
    if String.ends_with?(loser, "a"), do: "da", else: "do"
  end
end
