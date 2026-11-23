defmodule Tymeslot.Emails.Shared.ButtonsTest do
  use Tymeslot.DataCase, async: true
  @moduletag :emails

  alias Tymeslot.Emails.Shared.Buttons
  alias Tymeslot.Utils.Colour

  describe "action_button/4" do
    test "includes the URL and label in output for a valid https URL" do
      html = Buttons.action_button(:confirmed, "Book Now", "https://example.com/book")

      assert html =~ "https://example.com/book"
      assert html =~ "Book Now"
    end

    test "renders nothing for an unsafe or missing URL" do
      assert Buttons.action_button(:confirmed, "Click", "javascript:alert(1)") == ""
      assert Buttons.action_button(:confirmed, "Click", nil) == ""
    end

    test "passes mailto: URL through unchanged" do
      html = Buttons.action_button(:confirmed, "Email Us", "mailto:support@example.com")

      assert html =~ "mailto:support@example.com"
    end

    test "full_width: true produces a different output than the default" do
      html_full = Buttons.action_button(:confirmed, "Go", "https://example.com", full_width: true)
      html_default = Buttons.action_button(:confirmed, "Go", "https://example.com")

      refute html_full == html_default
      assert html_full =~ "mobile-button"
      refute html_default =~ "mobile-button"
    end

    # Revision Dynamics (rd-mail-brand.patch): the one primary button carries
    # the product tone whatever the intent; signals colour the eyebrow.
    test "renders on the product tone's solid face for every intent" do
      for intent <- [:confirmed, :alert, :cancelled] do
        html = Buttons.action_button(intent, "Go", "https://example.com")
        product = Tymeslot.Emails.Shared.Styles.Tokens.tone()

        assert html =~ ~s(background-color="#{product.solid}")
        assert html =~ ~s(color="#{product.on}")
      end
    end

    test "every product tone's button clears 4.5:1" do
      for tone <- Tymeslot.Emails.Shared.Styles.Tone.all() do
        family = Tymeslot.Emails.Shared.Styles.Tone.family(tone)

        html =
          Tymeslot.Emails.Shared.Styles.Tone.with_tone(tone, fn ->
            Buttons.action_button(:confirmed, "Go", "https://example.com")
          end)

        assert html =~ ~s(background-color="#{family.solid}")
        assert Colour.contrast_ratio(family.on, family.solid) >= 4.5
        assert Colour.contrast_ratio(family.dark.on, family.dark.solid) >= 4.5
      end
    end
  end
end
