defmodule Tymeslot.Emails.Shared.Styles.DarkModeTest do
  use ExUnit.Case, async: false

  @moduletag :emails

  alias Tymeslot.Emails.Shared.{Layouts, MjmlEmail, Styles}
  alias Tymeslot.Emails.Shared.Styles.Tone
  alias Tymeslot.Emails.Shared.Styles.{DarkMode, Tokens}
  alias Tymeslot.Utils.Colour

  # The `:confirmed` family follows the configured accent, so tests that move
  # it restore the original afterwards.
  setup do
    original = Application.get_env(:tymeslot, :email_brand_accent)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:tymeslot, :email_brand_accent)
        value -> Application.put_env(:tymeslot, :email_brand_accent, value)
      end
    end)

    :ok
  end

  describe "stylesheet/1" do
    test "puts every rule inside the dark colour-scheme media query" do
      css = DarkMode.stylesheet(%{text: [{"#111418", "#f2eee4"}]})

      [_before, inside] = String.split(css, "@media (prefers-color-scheme: dark) {", parts: 2)
      assert inside =~ "{color:#f2eee4 !important;}"
      refute css =~ ~r/\}\s*\[style/, "a rule escaped the media query"
    end

    test "anchors text selectors so a background of the same colour is left alone" do
      css = DarkMode.stylesheet(%{text: [{"#111418", "#f2eee4"}]})

      assert css =~ ~s([style^="color:#111418"])
      assert css =~ ~s([style*=";color:#111418"])
      assert css =~ ~s([style*="; color: #111418"])
      # An unanchored `color:#111418` would also match `background-color:#111418`.
      refute css =~ ~s([style*="color:#111418"])
    end

    test "matches backgrounds written as shorthand, longhand or bgcolor" do
      css = DarkMode.stylesheet(%{background: [{"#fafaf6", "#1b1e21"}]})

      for selector <- [
            ~s([bgcolor="#fafaf6"]),
            ~s([style*="background:#fafaf6"]),
            ~s([style*="background: #fafaf6"]),
            ~s([style*="background-color:#fafaf6"]),
            ~s([style*="background-color: #fafaf6"])
          ] do
        assert css =~ selector
      end

      assert css =~ "{background-color:#1b1e21 !important;}"
    end

    test "keeps a mapped text colour on its listed background with a more specific rule" do
      css =
        DarkMode.stylesheet(%{
          text: [{"#111418", "#f2eee4"}],
          keep_text: [{"#d97706", "#111418"}]
        })

      assert css =~ ~s([style*="#d97706"][style*="color:#111418"])
      assert css =~ "{color:#111418 !important;}"
    end
  end

  describe "the email palette" do
    test "every dark text colour reads against every dark surface text sits on" do
      assert low_contrast_pairs(Styles.dark_mode_styles()) == []
    end

    # Revision Dynamics (rd-mail-brand.patch): every product tone.
    test "every product tone yields readable dark text" do
      for tone <- Tone.all() do
        pairs = Tone.with_tone(tone, fn -> low_contrast_pairs(Styles.dark_mode_styles()) end)

        assert pairs == [], "#{tone}"
      end
    end

    test "the primary button takes the tone's dark face and ink" do
      for tone <- Tone.all() do
        family = Tone.family(tone)
        css = Tone.with_tone(tone, &Styles.dark_mode_styles/0)

        assert css =~ ~s([bgcolor="#{family.solid}"]), "#{tone}"
        assert css =~ "{background-color:#{family.dark.solid} !important;}", "#{tone}"

        assert css =~ "{color:#{family.dark.on} !important;}", "#{tone}"
        assert Colour.contrast_ratio(family.dark.on, family.dark.solid) >= 4.5
      end
    end
  end

  describe "rendered into an email" do
    test "the compiled HTML carries the dark stylesheet once, in the head" do
      html =
        "<mj-section><mj-column><mj-text>Body</mj-text></mj-column></mj-section>"
        |> Layouts.system_layout(intent: :confirmed, eyebrow: "Welcome")
        |> MjmlEmail.compile_mjml()

      [head, _body] = String.split(html, "</head>", parts: 2)

      assert length(String.split(html, "prefers-color-scheme: dark")) == 2
      assert head =~ "prefers-color-scheme: dark"
      assert head =~ ~s([bgcolor="#{Tokens.canvas()}"])
    end
  end

  # Every `{text, background}` pairing of the stylesheet's dark text colours
  # with its dark backgrounds that falls under WCAG AA. Revision Dynamics
  # (rd-mail-brand.patch): the hairlines carry no text, and the button faces
  # and the accent rule carry only the button's own ink (checked above), so
  # they are left out, as is that ink.
  defp low_contrast_pairs(css) do
    families = [Tone.family(), Tone.signal(:alert), Tone.signal(:cancelled)]
    faces = Enum.flat_map(families, &[&1.dark.solid, &1.dark.accent])

    texts = (css |> dark_values("color")) -- [Tone.family().dark.on]

    backgrounds =
      (css |> dark_values("background-color")) --
        ([Tokens.dark(:hairline), Tokens.dark(:hairline_soft)] ++ faces)

    assert texts != [] and backgrounds != []

    for text <- texts,
        background <- backgrounds,
        Colour.contrast_ratio(text, background) < 4.5,
        do: {text, background}
  end

  defp dark_values(css, property) do
    ~r/\{#{property}:(#[0-9a-f]{6}) !important;\}/
    |> Regex.scan(css, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end
end
