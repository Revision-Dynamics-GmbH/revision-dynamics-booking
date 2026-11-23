defmodule TymeslotWeb.FallbackControllerTest do
  use TymeslotWeb.ConnCase, async: true
  @moduletag :utils

  describe "GET / (fallback)" do
    test "returns a real 404 for unmatched paths", %{conn: conn} do
      # We need to trigger the fallback.
      # Paths like "/foo" are caught by the /:username route.
      # Paths with multiple segments like "/foo/bar" should hit the fallback.

      conn = get(conn, "/invalid/path/to/trigger/fallback")
      assert conn.status == 404
    end

    # Revision Dynamics (rd-mail-brand.patch): a self-contained page in the
    # website's look whose actions lead to the website, where the booking is.
    test "renders the branded 404 page with a way back to the website", %{conn: conn} do
      body = conn |> get("/invalid/path/to/trigger/fallback") |> response(404)

      assert body =~ "This page does not exist."
      assert body =~ "<!DOCTYPE html>"
      assert body =~ ~s(href="https://revisiondynamics.com/en/termin")
      assert body =~ "<title>Page not found · Revision Dynamics</title>"
    end

    test "emits no canonical link advertising the missing URL", %{conn: conn} do
      # The root layout carries a self-referential <link rel="canonical">. On a
      # 404 that would tell crawlers a dead page is its own canonical, so the
      # error response must render without it.
      conn = get(conn, "/invalid/path/to/trigger/fallback")
      refute response(conn, 404) =~ "rel=\"canonical\""
    end
  end
end
