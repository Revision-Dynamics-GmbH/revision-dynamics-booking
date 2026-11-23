defmodule Tymeslot.Emails.Shared.Stage do
  @moduledoc """
  The **stage** — the opening of every email's card.

  Revision Dynamics (rd-mail-brand.patch): the shared mail design opens the
  card with a 4px accent rule in the product tone, then three typographic
  elements on the white card, left-aligned as on the website:

  1. An **eyebrow** in spaced capitals (13px), naming product and occasion
     ("HumanOS · Confirmed"); coloured by the intent, so a cancellation or an
     alert reads as one before a word is read
  2. The **title** (Urbanist 500, 30px, 26px on a phone), a statement rather
     than an exclamation
  3. An optional **lead** (18px, 16px on a phone)

  The intent (`:confirmed`, `:alert`, `:cancelled`) picks the eyebrow's
  colour (`Tymeslot.Emails.Shared.Styles.intent/1`); the rule always carries
  the product tone (`Tymeslot.Emails.Shared.Styles.Tone`).
  """

  alias Tymeslot.Emails.Shared.{Sanitise, Styles}
  alias Tymeslot.Emails.Shared.Styles.{Tokens, Tone}

  use Gettext, backend: TymeslotWeb.Gettext

  @doc """
  The stage option `key` (`:intent` or `:eyebrow`) from `opts`, a keyword
  list or a map. Raises `ArgumentError` naming the key when it is missing:
  every email declares its stage at the call site, and nothing infers it from
  a title or falls back to a default. The one check every layout and helper
  that renders a stage band uses.
  """
  @spec fetch_required!(keyword() | map(), atom()) :: term()
  def fetch_required!(opts, key) do
    case Access.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
              "missing required stage option `#{inspect(key)}`: every email must declare " <>
                "`:intent` and `:eyebrow` at the call site."
    end
  end

  @doc """
  Renders the stage section.

  `intent` is an atom — see `Styles.intent/1`.

  String arguments (eyebrow, title, subtitle) are sanitised inside this
  function — callers do not need to pre-sanitise them.
  """
  @spec stage_band(atom(), String.t(), String.t(), String.t() | nil) :: String.t()
  def stage_band(intent, eyebrow, title, subtitle \\ nil) do
    tokens = Styles.intent(intent)
    product = Tokens.tone()
    safe_eyebrow = Sanitise.sanitize_for_email(eyebrow_with_product(eyebrow))
    safe_title = Sanitise.sanitize_for_email(title)

    subtitle_block =
      case subtitle do
        nil ->
          ""

        "" ->
          ""

        s ->
          safe_subtitle = Sanitise.sanitize_for_email(s)

          """
          <mj-text
            padding="16px 0 0 0"
            color="#{Tokens.ink_soft()}"
            font-size="#{Tokens.font_size(:lg)}"
            line-height="1.6"
            align="left"
            css-class="rd-lead mobile-text"
          >
            #{safe_subtitle}
          </mj-text>
          """
      end

    """
    <mj-section
      background-color="#{Tokens.surface()}"
      padding="32px 36px 8px 36px"
      border-top="4px solid #{product.accent}"
      border-radius="15px 15px 0 0"
      css-class="stage-band"
    >
      <mj-column>
        <mj-text
          padding="0 0 14px 0"
          color="#{tokens.accent_deep}"
          font-size="#{Tokens.font_size(:eyebrow)}"
          font-weight="500"
          align="left"
          line-height="1.2"
          letter-spacing="0.14em"
          text-transform="uppercase"
          css-class="stage-band-eyebrow mobile-eyebrow"
        >
          #{safe_eyebrow}
        </mj-text>
        <mj-text
          padding="0"
          color="#{Tokens.ink()}"
          font-family="#{Tokens.heading_font_family()}"
          font-size="#{Styles.font_size(:display)}"
          font-weight="500"
          align="left"
          line-height="1.15"
          letter-spacing="0"
          css-class="stage-band-title mobile-heading"
        >
          #{safe_title}
        </mj-text>
        #{subtitle_block}
      </mj-column>
    </mj-section>
    """
  end

  # The eyebrow names the product first when the email is about one, as the
  # website's section kickers do: "HumanOS · Confirmed".
  defp eyebrow_with_product(eyebrow) do
    case product_name(Tone.current()) do
      nil -> eyebrow
      name -> "#{name} · #{eyebrow}"
    end
  end

  @doc "The product a tone stands for, as its name is written everywhere; nil for cyan."
  @spec product_name(Tone.t()) :: String.t() | nil
  def product_name(:orange), do: "HumanOS"
  def product_name(:blue), do: "OrganisationOS"
  def product_name(:violet), do: "Education Lab"
  def product_name(_cyan), do: nil
end
