defmodule Tymeslot.Emails.Shared.Styles.Tokens do
  @moduledoc """
  The design-token primitives of every email.

  Revision Dynamics (rd-mail-brand.patch): the values are the website's
  (`app/globals.css`, light theme as the fallback every client shows, dark
  theme for `prefers-color-scheme: dark`) and follow the shared Revision
  Dynamics mail design (README in `~/outputs/mail-design-2026-11-23/`):
  a light blue-grey canvas, a white card, the website's ink roles, Outfit
  and Urbanist with system fallbacks, and the website's type scale converted
  to fixed pixels.

  This module carries the raw values and the lookup functions that turn
  token keys into values. Nothing in here emits CSS:
  `Tymeslot.Emails.Shared.Styles.CSS` does that.

  Colour families come from `Tymeslot.Emails.Shared.Styles.Tone`: the
  `:confirmed` intent is the product tone of the email being rendered
  (HumanOS orange, OrganisationOS blue, Education Lab violet, otherwise cyan),
  `:alert` is gold and `:cancelled` red.
  """

  alias Tymeslot.Emails.Shared.Styles.Tone

  # ============================================================================
  # PALETTE — canvas, surfaces, ink, hairlines (website light theme)
  # ============================================================================

  # --color-bg, --color-inset, --color-surface-solid, --color-stroke,
  # --color-stroke-lines, --color-heading, --color-text, --color-text-muted.
  # Every text tier clears 4.5:1 on the card and the inset (README 2.1).
  @canvas "#f1f6fc"
  @canvas_soft "#f3f6fa"
  @surface "#ffffff"
  @hairline "#d6deea"
  @hairline_soft "#e3e8f0"

  @ink "#071832"
  @ink_soft "#263958"
  @ink_muted "#5b6785"
  @ink_whisper "#5b6785"

  # The website's dark theme, applied under `prefers-color-scheme: dark` by
  # `Styles.DarkMode`.
  @dark %{
    canvas: "#010a19",
    canvas_soft: "#0b172b",
    surface: "#040c1b",
    hairline: "#2a3650",
    hairline_soft: "#152139",
    ink: "#ffffff",
    ink_soft: "#dbe3f6",
    ink_muted: "#a9b6d8",
    ink_whisper: "#a9b6d8"
  }

  # ============================================================================
  # INTENTS — semantic categories describing the purpose of an email. Each
  # exposes the same shape, so callers never care which family backs them.
  # ============================================================================

  @type intent :: :confirmed | :alert | :cancelled

  @type intent_tokens :: %{
          accent: String.t(),
          accent_deep: String.t(),
          accent_ink: String.t(),
          tint: String.t(),
          band_color: String.t(),
          band_text: String.t(),
          solid: String.t(),
          on: String.t(),
          edge: String.t(),
          dark: map()
        }

  # ============================================================================
  # TYPOGRAPHY — Outfit for text, Urbanist for titles and buttons, each with
  # the system fallbacks every client has. The web fonts load only from the
  # booking host itself (`CSS.font_face_styles/0`); Outlook for Windows is
  # pinned to Segoe UI so it never falls back to Times.
  # ============================================================================

  @font_family "Outfit, 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, Helvetica, Arial, sans-serif"
  @heading_font_family "Urbanist, Outfit, 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, Helvetica, Arial, sans-serif"

  # The website's type scale (`--type-*`) in fixed pixels: titles 30 px
  # (26 on a phone), lead 18, body 16, card text 15, eyebrows and the foot 13.
  # Nothing is smaller than 13 px.
  @font_sizes %{
    eyebrow: "13px",
    xs: "13px",
    sm: "15px",
    md: "16px",
    base: "16px",
    lg: "18px",
    xl: "20px",
    "2xl": "24px",
    "3xl": "30px",
    display: "30px",
    hero: "30px"
  }

  # ============================================================================
  # RADII — buttons and panels 8 px like the website's `.btn` and
  # `--radius-md`, the card 16 px (`--radius-xl`). No pills.
  # ============================================================================

  @radii %{sm: "8px", md: "8px", lg: "16px", pill: "8px"}

  # ============================================================================
  # PUBLIC GETTERS
  # ============================================================================

  @doc "Canvas — outer background of every email."
  @spec canvas() :: String.t()
  def canvas, do: @canvas

  @doc "Inset — the quiet panel inside the card (meeting details, foot)."
  @spec canvas_soft() :: String.t()
  def canvas_soft, do: @canvas_soft

  @doc "Card surface."
  @spec surface() :: String.t()
  def surface, do: @surface

  @doc "Hairline — 1px dividers and panel borders."
  @spec hairline() :: String.t()
  def hairline, do: @hairline

  @doc "Soft hairline — the quietest dividers."
  @spec hairline_soft() :: String.t()
  def hairline_soft, do: @hairline_soft

  @doc "Heading ink — titles and values."
  @spec ink() :: String.t()
  def ink, do: @ink

  @doc "Text ink — body paragraphs."
  @spec ink_soft() :: String.t()
  def ink_soft, do: @ink_soft

  @doc "Muted ink — labels, eyebrows, secondary metadata, the foot."
  @spec ink_muted() :: String.t()
  def ink_muted, do: @ink_muted

  @doc "Whisper ink — the quietest text; the same as muted, never below 4.5:1."
  @spec ink_whisper() :: String.t()
  def ink_whisper, do: @ink_whisper

  @doc """
  The dark counterpart of a neutral token (`:canvas`, `:surface`, `:ink`, …),
  used by the dark-mode stylesheet.
  """
  @spec dark(atom()) :: String.t()
  def dark(key), do: Map.fetch!(@dark, key)

  @doc "Text font stack: Outfit, then system fonts."
  @spec font_family() :: String.t()
  def font_family, do: @font_family

  @doc "Title and button font stack: Urbanist, then Outfit, then system fonts."
  @spec heading_font_family() :: String.t()
  def heading_font_family, do: @heading_font_family

  @doc "Font size by semantic key."
  @spec font_size(atom()) :: String.t()
  def font_size(key), do: Map.fetch!(@font_sizes, key)

  @doc "Border radius by semantic key."
  @spec radius(:sm | :md | :lg | :pill) :: String.t()
  def radius(key), do: Map.fetch!(@radii, key)

  @doc """
  Full token map for an intent. Raises on unknown input — intents are
  declared by the caller, never inferred or guessed.

  `:confirmed` is the product tone of the email being rendered
  (`Tone.with_tone/2`, cyan outside it).
  """
  @spec intent(intent()) :: intent_tokens()
  def intent(:confirmed), do: family_tokens(Tone.family())
  def intent(:alert), do: family_tokens(Tone.signal(:alert))
  def intent(:cancelled), do: family_tokens(Tone.signal(:cancelled))

  @doc """
  The product tone's tokens, whatever the email's intent: the accent rule,
  the card's edge and the primary button always carry the product.
  """
  @spec tone() :: intent_tokens()
  def tone, do: family_tokens(Tone.family())

  defp family_tokens(family) do
    %{
      accent: family.accent,
      accent_deep: family.deep,
      accent_ink: family.ink,
      tint: family.tint,
      band_color: family.deep,
      band_text: family.on,
      solid: family.solid,
      on: family.on,
      edge: family.edge,
      dark: family.dark
    }
  end

  @doc "Shortcut for `intent(i).accent`."
  @spec intent_accent(intent()) :: String.t()
  def intent_accent(i), do: intent(i).accent

  @doc "Shortcut for `intent(i).accent_deep` — text and links in the intent's colour."
  @spec intent_accent_deep(intent()) :: String.t()
  def intent_accent_deep(i), do: intent(i).accent_deep
end
