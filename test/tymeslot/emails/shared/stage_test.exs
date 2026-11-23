defmodule Tymeslot.Emails.Shared.StageTest do
  use Tymeslot.DataCase, async: true
  @moduletag :emails

  alias Tymeslot.Emails.Shared.{Layouts, MjmlEmail, Stage}
  alias Tymeslot.Emails.Shared.Styles

  describe "stage_band/4" do
    test "includes the title and subtitle in output" do
      html = Stage.stage_band(:confirmed, "Confirmed", "Your meeting is booked", "See you soon")

      assert html =~ "Your meeting is booked"
      assert html =~ "See you soon"
    end

    test "includes the eyebrow in output" do
      html = Stage.stage_band(:confirmed, "Confirmed", "Title")

      assert html =~ "Confirmed"
    end

    # Revision Dynamics (rd-mail-brand.patch): the stage sits on the white
    # card; nothing in it is translucent, and the rule carries the product tone.
    test "draws the eyebrow and subtitle at full contrast" do
      html = Stage.stage_band(:alert, "Security", "Title", "A subtitle")

      refute html =~ "opacity"
      assert html =~ ~s(border-top="4px solid #{Styles.Tokens.tone().accent})
      assert html =~ ~s(color="#{Styles.intent_accent_deep(:alert)}")
      refute Styles.email_css_styles() =~ ~r/\.stage-band-eyebrow\s*\{[^}]*opacity/
    end

    test "omits the subtitle block when subtitle is nil" do
      html_with = Stage.stage_band(:confirmed, "Confirmed", "Title", "A subtitle")
      html_without = Stage.stage_band(:confirmed, "Confirmed", "Title", nil)

      assert html_with =~ "A subtitle"
      refute html_without =~ "A subtitle"
    end

    test "escapes special characters in the title" do
      html = Stage.stage_band(:confirmed, "Notice", "A & B")

      assert html =~ "A &amp; B"
      refute html =~ "A &amp;amp; B"
    end
  end

  describe "fetch_required!/2" do
    test "reads a stage option from a keyword list or a map" do
      assert Stage.fetch_required!([intent: :confirmed], :intent) == :confirmed
      assert Stage.fetch_required!(%{eyebrow: "Confirmed"}, :eyebrow) == "Confirmed"
    end

    test "raises naming the missing option" do
      assert_raise ArgumentError, ~r/`:eyebrow`/, fn ->
        Stage.fetch_required!([intent: :confirmed], :eyebrow)
      end

      assert_raise ArgumentError, ~r/`:intent`/, fn -> Stage.fetch_required!(%{}, :intent) end
    end
  end

  test "every layout refuses an email that declares no intent" do
    assert_raise ArgumentError, ~r/`:intent`/, fn ->
      Layouts.system_layout("", title: "T", eyebrow: "E")
    end

    assert_raise ArgumentError, ~r/`:intent`/, fn ->
      MjmlEmail.base_mjml_template("", %{eyebrow: "E", name: "N"})
    end
  end
end
