defmodule Tymeslot.Emails.Shared.Buttons do
  @moduledoc """
  Primary call-to-action buttons for Tymeslot emails — 2026 redesign.

  Single-CTA ethos. Revision Dynamics (rd-mail-brand.patch): the face is the
  product tone of the email (HumanOS orange, OrganisationOS blue, Education
  Lab violet, otherwise cyan); `intent` is accepted for compatibility.
  """

  alias Tymeslot.Emails.Shared.{Sanitise, Styles}
  alias Tymeslot.Emails.Shared.Styles.Tokens

  @doc """
  A primary action button — pill-shaped, bold, centred. The background colour
  comes from the supplied `intent`. Renders nothing when `url` is missing or
  not safe to link (`Sanitise.safe_url?/1`).

  Options:
  - `:size` — `:large`, `:medium`, `:small` (default: `:medium`)
  - `:full_width` — mobile responsiveness (default: `false`)
  - `:width` — explicit width (default: `"auto"`)
  """
  @spec action_button(Tokens.intent(), String.t(), String.t() | nil, keyword()) :: String.t()
  def action_button(intent, text, url, opts \\ []) when is_atom(intent) do
    case Sanitise.sanitize_url(url) do
      nil -> ""
      safe_url -> button_section(intent, text, safe_url, opts)
    end
  end

  # Revision Dynamics (rd-mail-brand.patch): the website's `.btn`: 8px
  # corners, Urbanist 17px, at least 48px high, left-aligned under the text,
  # full width on a phone. The face is the product tone's solid colour
  # whatever the email's intent (`Tokens.tone/0`): the one primary action
  # always carries the product, signals colour the eyebrow instead.
  defp button_section(intent, text, safe_url, opts) do
    size = Keyword.get(opts, :size, :medium)
    full_width = Keyword.get(opts, :full_width, false)
    width = Keyword.get(opts, :width, "auto")

    """
    <mj-section padding="20px 0 8px 0">
      <mj-column>
        #{button_markup(intent, text, safe_url, size, full_width, width)}
      </mj-column>
    </mj-section>
    """
  end

  defp button_markup(_intent, text, safe_url, size, full_width, width) do
    safe_text = Sanitise.sanitize_for_email(text)
    css_class = if full_width, do: "mobile-button", else: ""
    product = Tokens.tone()

    """
    <mj-button
      href="#{safe_url}"
      background-color="#{product.solid}"
      color="#{product.on}"
      border-radius="#{Styles.button_radius()}"
      font-family="#{Tokens.heading_font_family()}"
      font-size="17px"
      inner-padding="#{Styles.button_padding(size)}"
      width="#{width}"
      align="left"
      font-weight="600"
      line-height="1.1"
      letter-spacing="0"
      css-class="#{css_class}">
      #{safe_text}
    </mj-button>
    """
  end
end
