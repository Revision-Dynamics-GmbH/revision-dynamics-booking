defmodule Tymeslot.Emails.Shared.Styles.Tone do
  @moduledoc """
  Revision Dynamics (rd-mail-brand.patch): the product tone of an email.

  Every Revision Dynamics email carries one tone, as the website's pages do
  (`app/ui/shared/navigation-tone.ts` in the website repository): HumanOS
  orange, OrganisationOS blue, Education Lab violet, everything else the cyan
  structure tone. The tone paints the accent rule at the top of the card,
  the card's edge, the eyebrow of a confirming email, the one primary button
  and the text links. Signals (`:alert` gold, `:cancelled` red) colour the
  eyebrow and callouts, never the button, so a cancelled HumanOS meeting still
  reads as a HumanOS email.

  A meeting email declares its tone with `with_tone/2` around its render; the
  tone is read from the meeting type's name or address
  (`for_source/1`). Everything rendered inside picks it up through
  `Tymeslot.Emails.Shared.Styles.Tokens`, so no component needs a new
  argument. Outside `with_tone/2` the tone is cyan.

  Each family carries its light values (the fallback every client shows) and
  the dark values `Tymeslot.Emails.Shared.Styles.CSS` swaps in under
  `prefers-color-scheme: dark`. Values come from the website's tokens
  (`--lg-*`, `--tone-*` in `app/globals.css`); every text pairing clears
  4.5:1 (see the mail design README, section 2).
  """

  @type t :: :cyan | :orange | :blue | :violet

  @type family :: %{
          accent: String.t(),
          deep: String.t(),
          ink: String.t(),
          tint: String.t(),
          solid: String.t(),
          on: String.t(),
          edge: String.t(),
          dark: %{
            accent: String.t(),
            deep: String.t(),
            ink: String.t(),
            tint: String.t(),
            solid: String.t(),
            on: String.t(),
            edge: String.t()
          }
        }

  @key {__MODULE__, :tone}

  # accent: decorative rule and wash; deep: text, links, eyebrow; ink: strong
  # text on tint; tint: callout surface; solid/on: button face and its label;
  # edge: the card's 1px border.
  @families %{
    cyan: %{
      accent: "#0aa5cc",
      deep: "#0a7194",
      ink: "#074f68",
      tint: "#ecf8fb",
      solid: "#0e7490",
      on: "#ffffff",
      edge: "#89d4e7",
      dark: %{
        accent: "#43deff",
        deep: "#8fe9ff",
        ink: "#c4f4ff",
        tint: "#08202e",
        solid: "#43deff",
        on: "#04202a",
        edge: "#184f64"
      }
    },
    orange: %{
      accent: "#f76806",
      deep: "#c2410c",
      ink: "#7c2d12",
      tint: "#fff4ec",
      solid: "#f76806",
      on: "#170800",
      edge: "#fbb787",
      dark: %{
        accent: "#f76806",
        deep: "#f99a52",
        ink: "#ffd2b0",
        tint: "#231208",
        solid: "#f76806",
        on: "#170800",
        edge: "#522914"
      }
    },
    blue: %{
      accent: "#3256ec",
      deep: "#3256ec",
      ink: "#1e3191",
      tint: "#eef1fe",
      solid: "#3256ec",
      on: "#ffffff",
      edge: "#9daef6",
      dark: %{
        accent: "#6f8cff",
        deep: "#6f8cff",
        ink: "#c9d4ff",
        tint: "#0f1838",
        solid: "#6f8cff",
        on: "#071131",
        edge: "#263564"
      }
    },
    violet: %{
      accent: "#9333ea",
      deep: "#7c3aed",
      ink: "#4c1d95",
      tint: "#f6effe",
      solid: "#7c3aed",
      on: "#ffffff",
      edge: "#cb9df5",
      dark: %{
        accent: "#c084fc",
        deep: "#c084fc",
        ink: "#ead5ff",
        tint: "#1b1233",
        solid: "#c084fc",
        on: "#160a2a",
        edge: "#403263"
      }
    }
  }

  # Signal families. They colour eyebrows and callouts, never a button, so
  # their `solid`/`on` only back the rare badge.
  @signals %{
    alert: %{
      accent: "#f2a925",
      deep: "#a16207",
      ink: "#713f12",
      tint: "#fdf6e3",
      solid: "#a16207",
      on: "#ffffff",
      edge: "#f5d48f",
      dark: %{
        accent: "#f2a925",
        deep: "#f7c45e",
        ink: "#fde7b0",
        tint: "#241b06",
        solid: "#f2a925",
        on: "#1d1300",
        edge: "#4a3a12"
      }
    },
    cancelled: %{
      accent: "#eb6265",
      deep: "#b42318",
      ink: "#7a271a",
      tint: "#fef3f2",
      solid: "#b42318",
      on: "#ffffff",
      edge: "#f3b1b2",
      dark: %{
        accent: "#eb6265",
        deep: "#ff9ea0",
        ink: "#ffd5d6",
        tint: "#2a0f12",
        solid: "#eb6265",
        on: "#1b0606",
        edge: "#5a2328"
      }
    }
  }

  # Names and addresses as they appear in meeting type names, slugs and
  # titles. "OrganizationOS" and "organization-os" are the website's older
  # spellings and still name the same product.
  @patterns [
    {:orange, ~r/human\s*-?\s*os/iu},
    {:blue, ~r/organi[sz]ation\s*-?\s*os/iu},
    {:violet, ~r/education\s*-?\s*lab/iu}
  ]

  @doc "The tone in effect for the email being rendered; cyan outside `with_tone/2`."
  @spec current() :: t()
  def current, do: Process.get(@key, :cyan)

  @doc "The colour family of the tone in effect."
  @spec family() :: family()
  def family, do: family(current())

  @doc "The colour family of `tone`."
  @spec family(t()) :: family()
  def family(tone), do: Map.fetch!(@families, tone)

  @doc "The colour family of a signal: `:alert` (gold) or `:cancelled` (red)."
  @spec signal(:alert | :cancelled) :: family()
  def signal(name), do: Map.fetch!(@signals, name)

  @doc "Every tone, for tests and previews."
  @spec all() :: [t()]
  def all, do: [:cyan, :orange, :blue, :violet]

  @doc """
  Runs `fun` with the tone of `source` in effect and restores the previous
  tone afterwards. `source` is a tone atom, or anything `for_source/1` reads
  a tone from (appointment details, a meeting, a meeting type).
  """
  @spec with_tone(t() | map() | nil, (-> result)) :: result when result: var
  def with_tone(source, fun) when is_function(fun, 0) do
    tone = if source in all(), do: source, else: for_source(source)
    previous = Process.get(@key)
    Process.put(@key, tone)

    try do
      fun.()
    after
      if previous, do: Process.put(@key, previous), else: Process.delete(@key)
    end
  end

  @doc """
  The tone a meeting's name or address names: HumanOS orange, OrganisationOS
  blue, Education Lab violet, otherwise cyan. Reads the meeting type's name,
  the meeting's title and the meeting type's slug, in both languages' wording,
  since a translated name still names the product.
  """
  @spec for_source(map() | String.t() | nil) :: t()
  def for_source(nil), do: :cyan

  def for_source(text) when is_binary(text), do: match(text) || :cyan

  # The first text that names a product decides, in the order of
  # `@text_keys`: the meeting type before a title that may also carry the
  # booker's institution.
  def for_source(%{} = source) do
    source
    |> texts()
    |> Enum.find_value(:cyan, &match/1)
  end

  def for_source(_other), do: :cyan

  @text_keys [
    :meeting_type,
    :meeting_type_name,
    :meeting_type_slug,
    :slug,
    :name,
    :title,
    :summary
  ]

  defp match(text) do
    Enum.find_value(@patterns, fn {tone, pattern} ->
      if Regex.match?(pattern, text), do: tone
    end)
  end

  defp texts(source) do
    own = Enum.map(@text_keys, &Map.get(source, &1))

    original =
      case Map.get(source, :original_texts) do
        %{} = texts -> Enum.map(@text_keys, &Map.get(texts, &1))
        _none -> []
      end

    Enum.filter(own ++ original, &is_binary/1)
  end
end
