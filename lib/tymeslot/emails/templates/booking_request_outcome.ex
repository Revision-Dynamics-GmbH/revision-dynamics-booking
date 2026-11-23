defmodule Tymeslot.Emails.Templates.BookingRequestOutcome do
  @moduledoc """
  Tells an invitee their booking request will not happen.

  Two variants, and the distinction is not pedantry:

    * `:declined` — the host read the request and said no. If they gave a
      reason it is quoted back, because a declined request without one reads
      as a system failure rather than a decision.
    * `:expired` — nobody answered before the deadline. The host did not
      refuse, and saying they did would be a lie about a real person. The
      wording keeps the door open and points at rebooking.

  Both close the loop the acknowledgement opened. An invitee told their time
  was held must be told when it stops being held, and the silence that would
  otherwise follow an unanswered request is the single worst outcome this
  feature can produce.

  A booking that was confirmed before and re-entered the gate through a
  reschedule (it has a `first_announced_at`) loses more than the requested
  time: releasing it cancels the booking itself. For it the email says so,
  and carries a cancellation `.ics` for the booking's UID, so the entry the
  original confirmation put in the invitee's calendar does not linger.

  Revision Dynamics (rd-request-fields.patch): addressed "Sehr geehrte/r"
  in the organiser's first person, a request with a title
  (`Tymeslot.Bookings.RequestFields`) named by it, and the way on is a new
  request on the website (`RdIdentity.request_url/1`), not the booking
  service's start page.
  """

  import Swoosh.Email

  alias Tymeslot.Bookings.RequestFields
  alias Tymeslot.ContentTranslations.AttendeeTexts
  alias Tymeslot.Emails.RecipientLocale

  alias Tymeslot.Emails.Shared.{
    Buttons,
    Formatting,
    MeetingComponents,
    MjmlEmail,
    RdIdentity,
    Sanitise,
    Styles,
    TemplateHelper,
    Text,
    TextBodyHelper,
    TimezoneHelper
  }

  alias Tymeslot.Emails.Shared.BookingRequestLocation
  alias Tymeslot.Integrations.Calendar.IcsGenerator
  alias Tymeslot.Meetings.MeetingSchema, as: Meeting

  use Gettext, backend: TymeslotWeb.Gettext

  @type variant :: :declined | :expired

  @spec render(variant(), Meeting.t()) :: Swoosh.Email.t()
  def render(variant, %Meeting{} = meeting) when variant in [:declined, :expired] do
    locale = RecipientLocale.attendee_locale(meeting)

    TemplateHelper.with_locale_and_tone(locale, meeting, fn ->
      # The stored title and texts are in the organiser's language; the booker
      # reads them in theirs.
      meeting = AttendeeTexts.attendee_view(meeting, locale)

      kind = if rescheduled?(meeting), do: :reschedule, else: :booking
      attendee_time = TimezoneHelper.convert_to_attendee_timezone(meeting)
      details = meeting_details(meeting, attendee_time)

      mjml_content = """
      #{Text.section_title(requested_time_title(kind))}
      #{MeetingComponents.meeting_details_table(details, locale)}

      #{Text.centered_text(dgettext("emails_booking_requests", "Dear %{name},", name: meeting.attendee_name) <> "\n\n" <> explanation({variant, kind}, meeting), padding: "16px 0")}

      #{reason_block({variant, kind}, meeting)}

      #{Buttons.action_button(:confirmed, dgettext("emails_booking_requests", "Request a new appointment"), RdIdentity.request_url(locale), full_width: true)}
      """

      html_body =
        TemplateHelper.compile_system_template(
          mjml_content,
          headline({variant, kind}),
          preheader({variant, kind}, meeting),
          intent: :cancelled,
          # A request is not a booking: its foot says the guest requested it.
          audience: if(kind == :booking, do: :requester, else: :guest),
          eyebrow: eyebrow({variant, kind}),
          stage_title: headline({variant, kind}),
          stage_subtitle:
            dgettext("emails_booking_requests", "Request to %{organizer}",
              organizer: meeting.organizer_name
            )
        )

      MjmlEmail.base_email()
      |> to({meeting.attendee_name, meeting.attendee_email})
      |> from({meeting.organizer_name, MjmlEmail.fetch_from_email()})
      |> MjmlEmail.put_reply_to(meeting.organizer_name, meeting.organizer_email)
      |> subject(
        subject_line(
          {variant, kind},
          meeting,
          if(RequestFields.request?(meeting),
            do: TemplateHelper.subject_moment(details, locale),
            else: Formatting.format_date_short(attendee_time, locale)
          )
        )
      )
      |> html_body(html_body)
      |> text_body(text_body_for({variant, kind}, meeting, details, locale))
      |> maybe_cancel_calendar_entry(kind, meeting, locale)
    end)
  end

  # Confirmed once already: the request was to move a booking, and releasing
  # it cancelled that booking.
  defp rescheduled?(%Meeting{first_announced_at: %DateTime{}}), do: true
  defp rescheduled?(_meeting), do: false

  defp requested_time_title(:booking), do: dgettext("emails_booking_requests", "Requested Time")

  defp requested_time_title(:reschedule),
    do: dgettext("emails_booking_requests", "Requested New Time")

  defp headline({:declined, :booking}),
    do: dgettext("emails_booking_requests", "Unfortunately, I cannot confirm your request.")

  defp headline({:expired, :booking}),
    do: dgettext("emails_booking_requests", "Your request has expired.")

  defp headline({:declined, :reschedule}),
    do: dgettext("emails_booking_requests", "Reschedule Declined")

  defp headline({:expired, :reschedule}),
    do: dgettext("emails_booking_requests", "Reschedule Request Expired")

  defp eyebrow({:declined, :booking}), do: dgettext("emails_booking_requests", "Not confirmed")
  defp eyebrow({:expired, :booking}), do: dgettext("emails_booking_requests", "Request expired")

  defp eyebrow({_variant, :reschedule}),
    do: dgettext("emails_booking_requests", "Booking cancelled")

  defp subject_line({:declined, :booking}, meeting, date) do
    case RequestFields.title(meeting) do
      nil ->
        dgettext("emails_booking_requests", "Request declined: %{title} - %{date}",
          title: meeting.title,
          date: date
        )

      title ->
        dgettext("emails_booking_requests", "Not confirmed: %{title} on %{date}",
          title: title,
          date: date
        )
    end
  end

  defp subject_line({:expired, :booking}, meeting, date) do
    case RequestFields.title(meeting) do
      nil ->
        dgettext("emails_booking_requests", "Request expired: %{title} - %{date}",
          title: meeting.title,
          date: date
        )

      title ->
        dgettext("emails_booking_requests", "Request expired: %{title} on %{date}",
          title: title,
          date: date
        )
    end
  end

  defp subject_line({:declined, :reschedule}, meeting, date) do
    dgettext(
      "emails_booking_requests",
      "Reschedule declined, booking cancelled: %{title} - %{date}",
      title: meeting.title,
      date: date
    )
  end

  defp subject_line({:expired, :reschedule}, meeting, date) do
    dgettext(
      "emails_booking_requests",
      "Reschedule request expired, booking cancelled: %{title} - %{date}",
      title: meeting.title,
      date: date
    )
  end

  defp preheader({:declined, :reschedule}, meeting) do
    dgettext("emails_booking_requests", "Hi %{name}, %{organizer} can't make the new time.",
      name: meeting.attendee_name,
      organizer: meeting.organizer_name
    )
  end

  defp preheader({:expired, :reschedule}, meeting) do
    dgettext(
      "emails_booking_requests",
      "Hi %{name}, your reschedule request wasn't answered in time.",
      name: meeting.attendee_name
    )
  end

  defp preheader({:declined, :booking}, meeting) do
    dgettext("emails_booking_requests", "%{organizer} cannot confirm the time you requested.",
      organizer: meeting.organizer_name
    )
  end

  defp preheader({:expired, :booking}, _meeting),
    do: dgettext("emails_booking_requests", "Your request was not confirmed in time.")

  defp explanation({:declined, :reschedule}, meeting) do
    dgettext(
      "emails_booking_requests",
      "%{organizer} wasn't able to accept the new time. Your previous time had already been given up for it, so your booking has been cancelled. The attached calendar file removes it from your calendar.",
      organizer: meeting.organizer_name
    )
  end

  defp explanation({:expired, :reschedule}, meeting) do
    dgettext(
      "emails_booking_requests",
      "%{organizer} didn't get to your reschedule request in time. Your previous time had already been given up for it, so your booking has been cancelled. The attached calendar file removes it from your calendar.",
      organizer: meeting.organizer_name
    )
  end

  defp explanation({:declined, :booking}, _meeting) do
    dgettext(
      "emails_booking_requests",
      "Unfortunately, I cannot confirm the appointment you requested, and the time is no longer held for you. You are welcome to request another appointment."
    )
  end

  defp explanation({:expired, :booking}, _meeting) do
    dgettext(
      "emails_booking_requests",
      "I was not able to confirm your request in time, so the time is no longer held for you. You are welcome to request another appointment."
    )
  end

  # A decline with a note reads as a person answering; without one it reads as
  # a machine. Where the host wrote nothing we say nothing rather than
  # inventing a reason on their behalf. `is_binary(reason)` alone accepts
  # `""`, which would print the "Note from …:" label with nothing under it, so
  # the empty string is excluded here rather than relied upon to have already
  # been normalised to `nil` upstream.
  defp reason_block({:declined, _kind}, %Meeting{decline_reason: reason} = meeting)
       when is_binary(reason) and reason != "" do
    """
    <mj-text font-size="15px" color="#{Styles.ink_soft()}" line-height="22px" padding="8px 0 0 0">
      #{dgettext("emails_booking_requests", "Note from %{organizer}:", organizer: meeting.organizer_name)}
    </mj-text>
    <mj-text font-size="15px" color="#{Styles.ink_soft()}" line-height="22px" font-style="italic" padding="4px 0 0 16px">
      #{reason |> Sanitise.sanitize_for_email() |> String.replace("\n", "<br/>")}
    </mj-text>
    """
  end

  defp reason_block(_outcome, _meeting), do: ""

  defp meeting_details(meeting, attendee_time) do
    %{
      date: attendee_time,
      start_time: attendee_time,
      start_time_attendee_tz: attendee_time,
      duration: meeting.duration,
      location: meeting.location,
      location_type: BookingRequestLocation.type(meeting),
      meeting_type: meeting.meeting_type || dgettext("emails_booking_requests", "Meeting"),
      request_title: RequestFields.title(meeting)
    }
  end

  defp text_body_for({_variant, _kind} = outcome, meeting, details, locale) do
    """
    #{headline(outcome)}

    #{dgettext("emails_booking_requests", "Dear %{name},", name: meeting.attendee_name)}

    #{explanation(outcome, meeting)}

    #{dgettext("emails_booking_requests", "REQUESTED TIME:")}
    #{TextBodyHelper.format_meeting_details(details, locale)}
    #{text_reason(outcome, meeting)}
    #{dgettext("emails_booking_requests", "Request a new appointment:")} #{RdIdentity.request_url(locale)}
    """
  end

  defp text_reason({:declined, _kind}, %Meeting{decline_reason: reason} = meeting)
       when is_binary(reason) and reason != "" do
    "\n" <>
      dgettext("emails_booking_requests", "Note from %{organizer}:",
        organizer: meeting.organizer_name
      ) <> "\n" <> reason <> "\n"
  end

  defp text_reason(_outcome, _meeting), do: ""

  # The original confirmation put this booking in the invitee's calendar under
  # its UID. `METHOD:PUBLISH` + `STATUS:CANCELLED`, as the ordinary
  # cancellation email sends (see `AppointmentCancellation`), with the next
  # sequence so the client treats it as newer than what it has on file.
  defp maybe_cancel_calendar_entry(email, :reschedule, meeting, locale) do
    attachment(
      email,
      IcsGenerator.generate_ics_cancel_attachment(
        # The `.ics` UID is the calendar identity, never the booking's
        # capability-bearing `uid`.
        meeting |> Map.from_struct() |> Map.put(:uid, meeting.calendar_uid),
        meeting.ical_sequence + 1,
        locale,
        "appointment-#{meeting.calendar_uid}.ics"
      )
    )
  end

  defp maybe_cancel_calendar_entry(email, :booking, _meeting, _locale), do: email
end
