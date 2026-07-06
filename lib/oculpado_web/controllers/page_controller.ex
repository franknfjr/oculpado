defmodule OculpadoWeb.PageController do
  use OculpadoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
