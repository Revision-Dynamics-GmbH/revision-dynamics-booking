defmodule TymeslotWeb.Themes.Shared.Components.LegalLinks do
  @moduledoc """
  The organiser's legal notice and privacy policy links, as a guest sees them
  at the foot of every public booking page.

  The links come from `Tymeslot.Profiles.public_legal_links/1`: the
  organiser's own, else the instance defaults. The page assigns them as
  `:legal_links` wherever it assigns `:organizer_profile`, and every theme's
  wrapper renders `footer/1` once, after the theme extensions and outside
  their `show_extensions` guard, so the payment return pages keep it. It sits
  inside the theme's page grid, which keeps it inside the booker root that
  the embed's auto-resize measures.

  Neutral class names here; the styling is shared by every theme, in
  `assets/css/scheduling/shared/components/legal-links.css`.

  Revision Dynamics (rd-mail-brand.patch): under the legal links a line says
  the booking service is based on Tymeslot (AGPL-3.0) and links the source of
  the version this page runs on, as the AGPL asks of a network service
  (§ 13), worded under Tymeslot's trademark rules. It points where the
  emails' notice does (`Tymeslot.Emails.Shared.RdIdentity.source_url/0`,
  `RD_SOURCE_URL`) and shows whether or not the organiser set legal links.
  """

  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  attr :links, :map,
    required: true,
    doc: "`%{legal_notice_url:, privacy_policy_url:}`, either URL nil, or nil for none"

  @doc """
  Renders a link for each URL set, the legal notice first, then the source
  code link, each opening in a new tab.
  """
  @spec footer(map()) :: Phoenix.LiveView.Rendered.t()
  def footer(assigns) do
    assigns =
      assign(assigns,
        legal_notice_url:
          Tymeslot.Emails.Shared.RdIdentity.localize_site_link(
            assigns.links && assigns.links[:legal_notice_url]
          ),
        privacy_policy_url:
          Tymeslot.Emails.Shared.RdIdentity.localize_site_link(
            assigns.links && assigns.links[:privacy_policy_url]
          ),
        source_url: Tymeslot.Emails.Shared.RdIdentity.source_url()
      )

    ~H"""
    <footer
      class="legal-links"
      data-testid="legal-links"
    >
      <a
        :if={@legal_notice_url}
        href={@legal_notice_url}
        target="_blank"
        rel="noopener noreferrer"
        class="legal-links__link"
      >
        {dgettext("booking", "Legal notice")}
      </a>
      <a
        :if={@privacy_policy_url}
        href={@privacy_policy_url}
        target="_blank"
        rel="noopener noreferrer"
        class="legal-links__link"
      >
        {dgettext("booking", "Privacy policy")}
      </a>
      <p class="legal-links__notice">
        {dgettext(
          "booking",
          "The booking service is based on Tymeslot, free software under the AGPL-3.0."
        )}
        <a
          href={@source_url}
          target="_blank"
          rel="noopener noreferrer"
          class="legal-links__link"
          data-testid="source-code-link"
        >
          {dgettext("booking", "Source code of our version")}
        </a>
      </p>
    </footer>
    """
  end
end
