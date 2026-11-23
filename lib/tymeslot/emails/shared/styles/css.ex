defmodule Tymeslot.Emails.Shared.Styles.CSS do
  @moduledoc """
  Generates the MJML-embedded CSS for every email.

  Revision Dynamics (rd-mail-brand.patch): the shared Revision Dynamics mail
  design (README in `~/outputs/mail-design-2026-11-23/`).

  Outputs:

  - `mjml_base_attributes/0` — the `<mj-attributes>` block that sets sensible
    defaults on `mj-all`, `mj-text`, `mj-section`, `mj-column`, `mj-button`,
    and `mj-table`.
  - `email_css_styles/0` — the `<mj-style>` block with base and phone rules.
  - `dark_mode_styles/0` — the `prefers-color-scheme: dark` stylesheet, built
    by `DarkMode` from the light-to-dark colour map below, for the product
    tone of the email being rendered.
  - `font_face_styles/0` — Outfit and Urbanist from the booking host itself,
    and Segoe UI for Outlook for Windows.

  Every colour is also written inline, light: clients that ignore
  `prefers-color-scheme` (Gmail, Outlook for Windows) keep the light design.
  """

  alias Tymeslot.Emails.Shared.Styles.{DarkMode, Tokens, Tone}
  alias Tymeslot.Emails.Shared.Urls

  # Class on the header logo's wrapper. Kept for callers that still name it;
  # the plate itself is `rd-plate` (`RdIdentity.header_mjml/0`).
  @logo_plate_class "rd-plate"

  @doc """
  The `<mj-attributes>` block with global defaults — font, text, section,
  column, button, table.
  """
  @spec mjml_base_attributes() :: String.t()
  def mjml_base_attributes do
    """
    <mj-attributes>
      <mj-all font-family="#{Tokens.font_family()}" />
      <mj-text font-size="#{Tokens.font_size(:md)}" line-height="1.6" color="#{Tokens.ink_soft()}" padding="0" />
      <mj-section padding="0" />
      <mj-column padding="0" />
      <mj-button font-family="#{Tokens.heading_font_family()}" padding="0" />
      <mj-table font-family="#{Tokens.font_family()}" color="#{Tokens.ink()}" />
    </mj-attributes>
    """
  end

  @doc """
  The `<mj-style>` block — base typography, card and badge rules, phone.
  """
  @spec email_css_styles() :: String.t()
  def email_css_styles do
    """
    <mj-style>
      #{base_rules()}
      #{mobile_styles()}
    </mj-style>
    """
  end

  @doc "The class the header logo's wrapper carries, which the dark stylesheet targets."
  @spec logo_plate_class() :: String.t()
  def logo_plate_class, do: @logo_plate_class

  @doc """
  Outfit and Urbanist, loaded from the booking host's own `/fonts/` (the
  files `rd-brand.patch` ships), never from a third party. Clients that do not
  load web fonts (Gmail, Outlook) use the fallback stack. Outlook for Windows
  gets Segoe UI explicitly; without it, an unknown first font sends it to
  Times.
  """
  @spec font_face_styles() :: String.t()
  def font_face_styles do
    base = Urls.get_app_url()

    """
    <style type="text/css">
    @font-face { font-family: "Outfit"; font-style: normal; font-weight: 100 900; font-display: swap; src: url("#{base}/fonts/outfit-latin-wght-normal.woff2") format("woff2"); }
    @font-face { font-family: "Urbanist"; font-style: normal; font-weight: 100 900; font-display: swap; src: url("#{base}/fonts/urbanist-latin-wght-normal.woff2") format("woff2"); }
    </style>
    <!--[if mso]>
    <style type="text/css">body, table, td, p, a, span, div, h1, h2, h3 { font-family: "Segoe UI", Arial, sans-serif !important; }</style>
    <![endif]-->
    """
  end

  @doc """
  The dark-mode `<style>` element. Rendered on every call because the
  product tone (`Tone.current/0`) differs from email to email.

  Each light value written inline is swapped for its dark counterpart from
  the website's dark theme; the product tone and the two signals carry their
  own dark values (`Tone`).
  """
  @spec dark_mode_styles() :: String.t()
  def dark_mode_styles do
    product = Tone.family()
    signals = [Tone.signal(:alert), Tone.signal(:cancelled)]
    families = [product | signals]

    DarkMode.stylesheet(%{
      text:
        neutral_pairs([:ink, :ink_soft, :ink_muted, :ink_whisper]) ++
          Enum.flat_map(families, &family_text_pairs/1) ++
          [{product.on, product.dark.on}],
      background:
        neutral_pairs([:canvas, :canvas_soft, :surface, :hairline, :hairline_soft]) ++
          Enum.flat_map(families, &family_background_pairs/1),
      border:
        neutral_pairs([:hairline, :hairline_soft]) ++
          Enum.flat_map(families, &family_border_pairs/1),
      keep_text: [],
      rules: dark_class_rules(product)
    })
  end

  defp neutral_pairs(keys) do
    Enum.map(keys, &{apply(Tokens, &1, []), Tokens.dark(&1)})
  end

  defp family_text_pairs(family) do
    [
      {family.deep, family.dark.deep},
      {family.ink, family.dark.ink},
      {family.accent, family.dark.accent}
    ]
  end

  defp family_background_pairs(family) do
    [
      {family.tint, family.dark.tint},
      {family.solid, family.dark.solid},
      {family.accent, family.dark.accent}
    ]
  end

  defp family_border_pairs(family) do
    [
      {family.edge, family.dark.edge},
      {family.accent, family.dark.accent},
      {family.solid, family.dark.solid}
    ]
  end

  # Class-based rules carry no inline colour for the attribute selectors to
  # match, so their dark values are set by class. `body a` outranks the base
  # `a` rule without `!important`, so a link with an inline colour (a button)
  # keeps it.
  defp dark_class_rules(product) do
    """
    body a { color: #{product.dark.deep}; }
    .rd-plate { background-color: transparent !important; background-image: none !important; }
    .rd-logo-light { display: none !important; }
    .rd-logo-dark { display: block !important; max-height: none !important; overflow: visible !important; }
    .rd-card { background: #{Tokens.dark(:surface)} !important; border-color: #{product.dark.edge} !important; }
    .hairline { background: #{Tokens.dark(:hairline)} !important; }
    .badge-turquoise { background: #{product.dark.tint} !important; color: #{product.dark.ink} !important; }
    .badge-amber { background: #{Tone.signal(:alert).dark.tint} !important; color: #{Tone.signal(:alert).dark.ink} !important; }
    .badge-rose { background: #{Tone.signal(:cancelled).dark.tint} !important; color: #{Tone.signal(:cancelled).dark.ink} !important; }
    """
  end

  # ============================================================================
  # BASE RULES — typography, links, card, badges
  # ============================================================================

  defp base_rules do
    product = Tokens.tone()

    """
    a {
      color: #{product.accent_deep};
      text-decoration: underline;
    }
    a[x-apple-data-detectors] { color: inherit !important; text-decoration: none !important; }

    .wordmark {
      font-family: #{Tokens.heading_font_family()};
      font-weight: 600;
      letter-spacing: 0;
    }

    .stage-band-eyebrow {
      font-size: #{Tokens.font_size(:eyebrow)};
      font-weight: 500;
      letter-spacing: 0.14em;
      text-transform: uppercase;
    }
    .stage-band-title {
      /* Fallback for clients that strip MJML's inline attributes. */
      font-family: #{Tokens.heading_font_family()};
      font-size: #{Tokens.font_size(:display)};
      font-weight: 500;
      letter-spacing: 0;
      line-height: 1.15;
    }

    .hairline {
      height: 1px;
      background: #{Tokens.hairline()};
      line-height: 1px;
      font-size: 1px;
    }

    .badge {
      display: inline-block;
      padding: 4px 10px;
      border-radius: #{Tokens.radius(:sm)};
      font-size: #{Tokens.font_size(:xs)};
      font-weight: 500;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    #{badge_variants()}
    """
  end

  defp badge_variants do
    Enum.map_join(
      [
        {:turquoise, :confirmed},
        {:amber, :alert},
        {:rose, :cancelled}
      ],
      "\n",
      fn {name, intent} ->
        tokens = Tokens.intent(intent)
        ".badge-#{name} { background: #{tokens.tint}; color: #{tokens.accent_ink}; }"
      end
    )
  end

  # ============================================================================
  # PHONE RULES — the @media (max-width: 480px) block
  # ============================================================================

  defp mobile_styles do
    """
    @media only screen and (max-width: 480px) {
      .mobile-display { font-size: 26px !important; line-height: 1.15 !important; }
      .mobile-heading { font-size: 26px !important; line-height: 1.15 !important; }
      .mobile-text    { font-size: 16px !important; line-height: 1.6 !important; }
      .mobile-eyebrow { font-size: 13px !important; }
      .mobile-button  { width: 100% !important; }
      .mobile-button table, .mobile-button a { width: 100% !important; box-sizing: border-box !important; }
      .mobile-card > table > tbody > tr > td { padding-left: 16px !important; padding-right: 16px !important; }
      /* MJML puts a css-class on the outer div and the padding on the cell
         inside it; only the cell may change, or the card's rule moves in. */
      .stage-band > table > tbody > tr > td { padding: 28px 22px 4px 22px !important; }
      .rd-body > table > tbody > tr > td    { padding-left: 22px !important; padding-right: 22px !important; }
      .rd-lead        { font-size: 16px !important; }
      .rd-label       { display: block !important; width: auto !important; padding: 12px 0 2px 0 !important; }
      .rd-value       { display: block !important; width: auto !important; padding: 0 0 12px 0 !important; border-top: 0 !important; }
    }
    """
  end
end
