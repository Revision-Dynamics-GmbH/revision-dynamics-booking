defmodule Tymeslot.Bookings.InstitutionTitleTest do
  @moduledoc """
  The booker's institution or company (Revision Dynamics,
  rd-institution-title.patch): validated and normalised as the booking form
  sends it, kept in `attendee_company`, and naming the organiser's calendar
  event and Teams meeting "<meeting type> x <institution>", while the booker's
  own emails and `.ics` keep the title they have always had.
  """

  use Tymeslot.DataCase, async: true
  @moduletag :bookings

  import Mox
  import Tymeslot.Factory

  alias Ecto.UUID
  alias Tymeslot.Bookings.BookingTitle
  alias Tymeslot.Bookings.BuildParams
  alias Tymeslot.Bookings.Institution
  alias Tymeslot.Bookings.MeetingAttributes
  alias Tymeslot.Emails.AppointmentBuilder
  alias Tymeslot.Emails.Templates.AppointmentConfirmation
  alias Tymeslot.Integrations.Calendar.CalendarEventBuilder
  alias Tymeslot.Integrations.Calendar.IcsGenerator
  alias Tymeslot.Integrations.Video.EventDetails
  alias Tymeslot.Integrations.Video.Providers.TeamsProvider.Payload
  alias Tymeslot.Scheduling.RescheduleContext
  alias Tymeslot.Security.FieldValidators.InstitutionValidator

  setup :verify_on_exit!

  doctest Institution
  doctest InstitutionValidator, import: true

  describe "Institution.normalise/1" do
    test "makes one line of line breaks, tabs and control characters" do
      assert Institution.normalise("Montessori-Schule\r\n\tIdstein\u0007") ==
               "Montessori-Schule Idstein"
    end

    test "drops invisible format characters and collapses whitespace" do
      assert Institution.normalise("Kita\u200B  St.\u00A0Josef\u202E") == "Kita St. Josef"
    end

    test "keeps what a name may contain" do
      assert Institution.normalise(~s(Kita "Sonnenschein" & Co. KG)) ==
               ~s(Kita "Sonnenschein" & Co. KG)
    end

    test "is nil for a blank value, a value that is not text, or invalid UTF-8" do
      assert Institution.normalise(" \n ") == nil
      assert Institution.normalise(nil) == nil
      assert Institution.normalise(%{"a" => "b"}) == nil
      assert Institution.normalise(<<0xFF, 0xFE>>) == nil
    end
  end

  describe "InstitutionValidator.validate/2" do
    test "accepts 120 characters and refuses 121, counted once normalised" do
      assert InstitutionValidator.validate(String.duplicate("ä", 120)) == :ok
      assert InstitutionValidator.validate("  " <> String.duplicate("a", 120) <> "\n") == :ok

      assert {:error, "Institution or company is too long (maximum 120 characters)"} =
               InstitutionValidator.validate(String.duplicate("a", 121))
    end

    test "requires a value unless told otherwise" do
      for blank <- [nil, "", "   ", "\n\t", ["list"]] do
        assert InstitutionValidator.validate(blank) ==
                 {:error, "Institution or company is required"}

        assert InstitutionValidator.validate(blank, required: false) == :ok
      end
    end

    test "speaks the visitor's language" do
      Gettext.with_locale(TymeslotWeb.Gettext, "de", fn ->
        assert InstitutionValidator.validate("") ==
                 {:error, "Einrichtung oder Unternehmen ist erforderlich"}
      end)
    end
  end

  describe "BookingTitle.organiser_title/3" do
    test "names the meeting type and the institution" do
      assert BookingTitle.organiser_title(
               "HumanOS kennenlernen",
               "Max Mustermann",
               " Montessori-Schule\nIdstein "
             ) == "HumanOS kennenlernen x Montessori-Schule Idstein"
    end

    test "is the title with the booker's name when there is no institution" do
      Gettext.with_locale(TymeslotWeb.Gettext, "de", fn ->
        for none <- [nil, "", "  \n "] do
          assert BookingTitle.organiser_title("HumanOS im Detail", "Max Mustermann", none) ==
                   "HumanOS im Detail mit Max Mustermann"
        end
      end)
    end

    test "never ends in an x with nothing after it, nor starts with one" do
      for title <- [
            BookingTitle.organiser_title("Intro", "Max", " "),
            BookingTitle.organiser_title(nil, "Max", "Beispiel GmbH"),
            BookingTitle.organiser_title("  ", "Max", "Beispiel GmbH")
          ] do
        refute title =~ ~r/(^|\s)x\s*$/
        refute title =~ ~r/^\s*x\s/
      end
    end
  end

  describe "BookingTitle.localise/2 for the booker" do
    defp institution_booking(title \\ "HumanOS kennenlernen x Montessori-Schule Idstein") do
      %{
        title: title,
        meeting_type: "HumanOS kennenlernen",
        attendee_name: "Max Mustermann",
        attendee_company: "Montessori-Schule Idstein"
      }
    end

    test "reads the organiser's institution title as the title with the booker's name" do
      assert BookingTitle.localise(institution_booking(), "de") ==
               "HumanOS kennenlernen mit Max Mustermann"

      assert BookingTitle.localise(institution_booking(), "en") ==
               "HumanOS kennenlernen with Max Mustermann"
    end

    test "names the type as the booker reads it" do
      assert BookingTitle.localise_with_type(institution_booking(), "Discover HumanOS") ==
               "Discover HumanOS with Max Mustermann"
    end

    test "leaves a title renamed since, or naming another institution, as it is" do
      assert BookingTitle.localise(institution_booking("Workshop Idstein"), "de") ==
               "Workshop Idstein"

      assert BookingTitle.localise(institution_booking("HumanOS kennenlernen x Andere"), "de") ==
               "HumanOS kennenlernen x Andere"
    end
  end

  describe "a booking with an institution" do
    setup do
      stub(Tymeslot.CalendarMock, :get_booking_integration_info, fn _client ->
        {:ok, %{integration_id: 1, calendar_path: "primary"}}
      end)

      user = insert(:user, locale: "de")
      profile = insert(:profile, user: user, full_name: "Tim Thielmann")
      meeting_type = insert(:meeting_type, user: user, name: "HumanOS kennenlernen")

      %{user: user, profile: profile, meeting_type: meeting_type}
    end

    defp build_attrs(%{user: user, meeting_type: meeting_type}, form_data) do
      start = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second)

      %{
        meeting_uid: UUID.generate(),
        start_datetime: start,
        end_datetime: DateTime.add(start, 45, :minute),
        duration_minutes: 45,
        form_data:
          Map.merge(%{"name" => "Max Mustermann", "email" => "max@example.com"}, form_data),
        organizer_user_id: user.id,
        meeting_type_id: meeting_type.id,
        user_timezone: "Europe/Berlin",
        attendee_locale: "de"
      }
      |> BuildParams.new()
      |> MeetingAttributes.build()
    end

    test "is titled '<meeting type> x <institution>' and keeps the institution", context do
      attrs = build_attrs(context, %{"company" => " Montessori-Schule\n Idstein "})

      assert attrs.title == "HumanOS kennenlernen x Montessori-Schule Idstein"
      assert attrs.summary == attrs.title
      assert attrs.attendee_company == "Montessori-Schule Idstein"
    end

    test "without one keeps the title it always had", context do
      attrs = build_attrs(context, %{"company" => "  "})

      assert attrs.title == "HumanOS kennenlernen mit Max Mustermann"
      assert attrs.attendee_company == nil

      assert build_attrs(context, %{}).title == "HumanOS kennenlernen mit Max Mustermann"
    end

    test "names the Outlook event and the Teams meeting after the institution", context do
      meeting = insert_booking(context)

      assert CalendarEventBuilder.build_event_data(meeting).summary ==
               "HumanOS kennenlernen x Montessori-Schule Idstein"

      details = EventDetails.from_meeting(meeting)
      assert details.summary == "HumanOS kennenlernen x Montessori-Schule Idstein"

      assert {:ok, %{subject: "HumanOS kennenlernen x Montessori-Schule Idstein"}} =
               Payload.event_window(%{event_details: details})
    end

    test "sends the booker the subject and .ics title they always had", context do
      meeting = insert_booking(context)
      details = AppointmentBuilder.from_meeting(meeting)

      assert details.title == "HumanOS kennenlernen mit Max Mustermann"

      email = AppointmentConfirmation.render(:attendee, meeting.attendee_email, details)
      refute email.subject =~ "Montessori"
      # Revision Dynamics (rd-mail-brand.patch): the subject names the
      # meeting type and the date.
      assert email.subject =~ "HumanOS kennenlernen"

      ics = IcsGenerator.generate_ics_attachment(details, "de", "appointment.ics")
      assert ics.data =~ "HumanOS kennenlernen mit Max Mustermann"
      refute ics.data =~ " x Montessori"
    end

    test "tells the organiser which institution booked", context do
      meeting = insert_booking(context)

      details =
        meeting
        |> AppointmentBuilder.from_meeting()
        |> AppointmentBuilder.organizer_copy(meeting)

      email = AppointmentConfirmation.render(:organizer, "tim@example.com", details)

      assert email.html_body =~ "Einrichtung oder Unternehmen"
      assert email.html_body =~ "Montessori-Schule Idstein"
      assert email.text_body =~ "Einrichtung oder Unternehmen: Montessori-Schule Idstein"
      # The subject names the booker, as it always has.
      assert email.subject =~ "Max Mustermann"
    end

    test "is prefilled with its institution when the booker reschedules it", context do
      meeting = insert_booking(context)

      assert RescheduleContext.new(meeting, context.meeting_type).form_data["company"] ==
               "Montessori-Schule Idstein"

      old = insert(:meeting, attendee_company: nil)
      assert RescheduleContext.new(old, nil).form_data["company"] == ""
    end
  end

  defp insert_booking(%{user: user, profile: profile, meeting_type: meeting_type} = context) do
    attrs = build_attrs(context, %{"company" => "Montessori-Schule Idstein"})

    insert(:meeting,
      organizer_user_id: user.id,
      organizer_email: user.email,
      organizer_name: profile.full_name,
      meeting_type_id: meeting_type.id,
      meeting_type: attrs.meeting_type,
      title: attrs.title,
      summary: attrs.summary,
      attendee_name: attrs.attendee_name,
      attendee_email: attrs.attendee_email,
      attendee_company: attrs.attendee_company,
      attendee_locale: "de",
      attendee_timezone: "Europe/Berlin"
    )
  end
end
