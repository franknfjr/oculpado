defmodule OculpadoWeb.CulpadoLiveTest do
  use OculpadoWeb.ConnCase
  import Phoenix.LiveViewTest

  test "jogador votado sobe pro topo da lista", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/match/brazil-norway")

    # pega um jogador de número alto (fica embaixo na ordem inicial): Rayan #26 (id 1464966)
    html = render_click(view, "toggle", %{"id" => "1464966"})

    # extrai a ordem dos ids na lista renderizada
    order =
      Regex.scan(~r/id="player-(\d+)"/, html)
      |> Enum.map(fn [_, id] -> id end)

    IO.inspect(Enum.take(order, 3), label: "top 3 após 1 voto no 1464966")

    assert List.first(order) == "1464966"
  end
end
