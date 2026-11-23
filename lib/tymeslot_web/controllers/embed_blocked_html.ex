defmodule TymeslotWeb.EmbedBlockedHTML do
  @moduledoc """
  Renders the embed-unavailable notice page (see `EmbedBlockedController`).

  Deliberately self-contained: a full HTML document with inline styles and no
  app chrome, so it stays tiny and renders the same inside any embedding site.
  Revision Dynamics (rd-mail-brand.patch): drawn by
  `TymeslotWeb.Components.RdPage` in the website's look, compact and on a
  transparent canvas because it sits inside another site's frame.
  When a `parent_origin` is known, a small inline script posts
  `tymeslot-embed-blocked` to the embedder; the message type is a public
  cross-repo contract (see the WordPress plugin's `embed-detect.js`). The script
  is static and reads the origin from a `data-` attribute, so nothing is
  interpolated into JavaScript.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :csp_nonce, :string, default: nil
  attr :parent_origin, :string, default: nil

  @spec index(map()) :: Phoenix.LiveView.Rendered.t()
  def index(assigns) do
    ~H"""
    <TymeslotWeb.Components.RdPage.page
      lang={Gettext.get_locale(TymeslotWeb.Gettext)}
      page_title={dgettext("embed", "Booking unavailable")}
      title={dgettext("embed", "The booking cannot be embedded here.")}
      text={
        dgettext(
          "embed",
          "This website is not approved to show the booking. You can book an appointment on revisiondynamics.com."
        )
      }
      csp_nonce={@csp_nonce}
      robots="noindex, nofollow"
      compact
      data-parent-origin={@parent_origin}
    >
      <script :if={@parent_origin} nonce={@csp_nonce}>
        (function () {
          try {
            var origin = document.body.getAttribute("data-parent-origin");
            if (origin) {
              window.parent.postMessage({ type: "tymeslot-embed-blocked" }, origin);
            }
          } catch (e) {}
        })();
      </script>
    </TymeslotWeb.Components.RdPage.page>
    """
  end
end
