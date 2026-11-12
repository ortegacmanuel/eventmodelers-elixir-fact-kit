defmodule MyAppWeb.PageControllerTest do
  use MyAppWeb.ConnCase

  # Phoenix's scaffold test. Screens and controllers get no tests in this kit,
  # so it stays out of the default suite.
  @moduletag :extra

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end
end
