defmodule MyAppWeb.ErrorJSONTest do
  use MyAppWeb.ConnCase, async: true

  # Phoenix's scaffold test. Screens and controllers get no tests in this kit,
  # so it stays out of the default suite.
  @moduletag :extra

  test "renders 404" do
    assert MyAppWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert MyAppWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
