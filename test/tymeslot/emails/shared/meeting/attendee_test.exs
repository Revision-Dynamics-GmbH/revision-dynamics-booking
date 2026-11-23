defmodule Tymeslot.Emails.Shared.Meeting.AttendeeTest do
  use Tymeslot.DataCase, async: true
  @moduletag :emails

  alias Tymeslot.Emails.Shared.Meeting.Attendee
  alias Tymeslot.Emails.Shared.Styles

  describe "attendee_info_section/2" do
    test "renders required name and email rows" do
      html =
        Attendee.attendee_info_section(:confirmed, %{
          name: "Alice Example",
          email: "alice@example.com"
        })

      assert html =~ "Attendee Information"
      assert html =~ "Alice Example"
      assert html =~ "alice@example.com"
    end

    test "renders email as a mailto link in the intent's deep accent colour" do
      confirmed_colour = Styles.intent_accent_deep(:confirmed)

      html =
        Attendee.attendee_info_section(:confirmed, %{
          name: "Alice",
          email: "alice@example.com"
        })

      assert html =~ ~s(href="mailto:alice@example.com")
      assert html =~ "color: #{confirmed_colour}"
    end

    test "uses the cancelled intent colour when called with :cancelled" do
      cancelled_colour = Styles.intent_accent_deep(:cancelled)

      html =
        Attendee.attendee_info_section(:cancelled, %{
          name: "Alice",
          email: "alice@example.com"
        })

      assert html =~ "color: #{cancelled_colour}"
    end

    test "renders optional phone, company, timezone when provided" do
      html =
        Attendee.attendee_info_section(:confirmed, %{
          name: "Alice",
          email: "alice@example.com",
          phone: "+44 20 7946 0000",
          company: "Acme Ltd",
          timezone: "Europe/London"
        })

      assert html =~ "+44 20 7946 0000"
      assert html =~ "Acme Ltd"
      assert html =~ "Europe/London"
    end

    test "omits optional rows when the value is nil or empty" do
      html =
        Attendee.attendee_info_section(:confirmed, %{
          name: "Alice",
          email: "alice@example.com",
          phone: nil,
          company: "",
          timezone: nil
        })

      refute html =~ "Phone"
      refute html =~ "Institution or company"
      refute html =~ "Timezone"
    end

    test "labels the company as the booking form asks for it" do
      html =
        Attendee.attendee_info_section(:confirmed, %{
          name: "Alice",
          email: "alice@example.com",
          company: "Acme Ltd"
        })

      assert html =~ "Institution or company"
      assert html =~ "Acme Ltd"
    end

    test "sanitizes XSS in attendee name" do
      html =
        Attendee.attendee_info_section(:confirmed, %{
          name: "<script>alert('xss')</script>Alice",
          email: "alice@example.com"
        })

      refute html =~ "<script>alert"
      assert html =~ "Alice"
    end

    test "sanitizes XSS in optional values" do
      html =
        Attendee.attendee_info_section(:confirmed, %{
          name: "Alice",
          email: "alice@example.com",
          company: "<img src=x onerror=alert(1)>Acme"
        })

      refute html =~ "<img src=x"
      assert html =~ "Acme"
    end
  end

  describe "counterpart_section/2" do
    test "shows the institution or company the booker gave, escaped" do
      html =
        Attendee.counterpart_section(:confirmed, %{
          attendee_name: "Max Mustermann",
          attendee_email: "max@example.com",
          attendee_company: ~s(Kita "Sonnenschein" <Idstein> & Co)
        })

      assert html =~ "Institution or company"
      assert html =~ "Kita &quot;Sonnenschein&quot; &lt;Idstein&gt; &amp; Co"
      refute html =~ "<Idstein>"
    end

    test "shows no institution row for a booking without one" do
      for company <- [nil, ""] do
        html =
          Attendee.counterpart_section(:confirmed, %{
            attendee_name: "Max Mustermann",
            attendee_email: "max@example.com",
            attendee_company: company
          })

        refute html =~ "Institution or company"
      end

      html =
        Attendee.counterpart_section(:confirmed, %{
          attendee_name: "Max Mustermann",
          attendee_email: "max@example.com"
        })

      refute html =~ "Institution or company"
    end
  end

  describe "attendee_message_box/2" do
    test "returns an empty string for nil message" do
      assert Attendee.attendee_message_box(:confirmed, nil) == ""
    end

    test "returns an empty string for blank message" do
      assert Attendee.attendee_message_box(:confirmed, "") == ""
    end

    test "renders the heading and message body when present" do
      html = Attendee.attendee_message_box(:confirmed, "Looking forward to chatting!")

      assert html =~ "Message from attendee"
      assert html =~ "Looking forward to chatting!"
    end

    test "sanitizes XSS in the message body" do
      html =
        Attendee.attendee_message_box(:confirmed, "<script>alert('xss')</script>Hi there")

      refute html =~ "<script>alert"
      assert html =~ "Hi there"
    end

    test "uses the intent's accent rail and tint" do
      html = Attendee.attendee_message_box(:alert, "Heads up — running 5 minutes late.")

      tokens = Styles.intent(:alert)
      assert html =~ "border-left=\"4px solid #{tokens.accent}\""
      assert html =~ "background-color=\"#{tokens.tint}\""
    end
  end
end
