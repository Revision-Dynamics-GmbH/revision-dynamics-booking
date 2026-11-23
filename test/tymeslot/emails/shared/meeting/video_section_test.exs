defmodule Tymeslot.Emails.Shared.Meeting.VideoSectionTest do
  use Tymeslot.DataCase, async: true
  @moduletag :emails

  alias Tymeslot.Emails.Shared.Meeting.VideoSection
  alias Tymeslot.Utils.Colour

  describe "video_meeting_section/3" do
    test "sanitizes meeting URL" do
      malicious_url = "https://meet.example.com/<script>alert('xss')</script>"
      html = VideoSection.video_meeting_section(:confirmed, malicious_url)

      # URL should be sanitized in href attribute
      refute html =~ "<script>"
    end

    test "renders nothing for an unsafe or missing URL" do
      assert VideoSection.video_meeting_section(:confirmed, "javascript:alert(1)") == ""
      assert VideoSection.video_meeting_section(:confirmed, nil) == ""
      assert VideoSection.video_meeting_section(:confirmed, "mailto:host@example.com") == ""
    end

    test "includes meeting URL in button" do
      url = "https://meet.example.com/room123"
      html = VideoSection.video_meeting_section(:confirmed, url)

      assert html =~ url
      assert html =~ "Join online"
    end

    test "supports different intents" do
      url = "https://meet.example.com/room123"

      rendered =
        for intent <- [:confirmed, :alert, :cancelled] do
          html = VideoSection.video_meeting_section(intent, url)

          assert html =~ url
          assert html =~ "Join online"

          html
        end

      # Revision Dynamics (rd-mail-brand.patch): the join button carries the
      # product tone whatever the intent, so every render is alike.
      assert rendered |> Enum.uniq() |> length() == 1
    end

    test "allows custom title and button text" do
      url = "https://meet.example.com/room123"

      html =
        VideoSection.video_meeting_section(:confirmed, url,
          title: "Custom Title",
          button_text: "Custom Button"
        )

      assert html =~ "Custom Title"
      assert html =~ "Custom Button"
    end

    test "renders the join button on the product tone's solid face for every intent" do
      url = "https://meet.example.com/room123"
      product = Tymeslot.Emails.Shared.Styles.Tokens.tone()

      for intent <- [:confirmed, :alert, :cancelled] do
        html = VideoSection.video_meeting_section(intent, url)

        assert html =~ ~s(background-color="#{product.solid}")
        assert html =~ ~s(color="#{product.on}")
      end

      assert Colour.contrast_ratio(product.on, product.solid) >= 4.5
    end
  end

  describe "time_alert_badge/2" do
    test "sanitizes time text" do
      html = VideoSection.time_alert_badge(:alert, "<script>alert('xss')</script>30 minutes")

      refute html =~ "<script>"
      assert html =~ "30 minutes"
    end

    test "supports different intents" do
      rendered =
        for intent <- [:confirmed, :alert, :cancelled] do
          html = VideoSection.time_alert_badge(intent, "Time text")

          assert html =~ "Time text"

          html
        end

      # Each intent must paint its own colour band, so no two renders are alike.
      assert rendered |> Enum.uniq() |> length() == 3
    end
  end
end
