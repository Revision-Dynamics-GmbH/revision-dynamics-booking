defmodule Tymeslot.Emails.Templates.BookingRequestReceived do
  @moduledoc """
  Tells an invitee their booking request has arrived and is not yet confirmed.

  This is the first of two emails on a meeting type requiring the host's
  approval; the second is the ordinary `AppointmentConfirmation`, sent once
  they say yes. The split is the whole point of the feature, so the wording
  here has to be unambiguous: the time is held, nobody has agreed to it yet,
  and here is when they will know.

  A booking that was confirmed before and is back in the gate because the
  invitee moved it (it has a `first_announced_at`) gets the reschedule
  wording instead, with `opts[:previous_start_time]` shown when the caller
  knows it.

  Deliberately carries **no `.ics` attachment**. A calendar file is a promise
  the host has not made, and an invitee whose calendar already shows the
  meeting will not read the email that follows.

  Revision Dynamics (rd-request-fields.patch): addressed "Sehr geehrte/r"
  in the organiser's first person, like the confirmation, and it promises no
  reply time: it says until when the time is held and what happens after.
  A request with a title (`Tymeslot.Bookings.RequestFields`) names it in the
  subject and the details and repeats the booker's description.
  """

  import Swoosh.Email

  alias Tymeslot.Bookings.MeetingLinks
  alias Tymeslot.Bookings.RequestFields

  alias Tymeslot.ContentTranslations.AttendeeTexts
  alias Tymeslot.Emails.RecipientLocale

  alias Tymeslot.Emails.Shared.{
    Formatting,
    MeetingComponents,
    MjmlEmail,
    Sanitise,
    Styles,
    TemplateHelper,
    Text,
    TextBodyHelper,
    TimezoneHelper
  }

  alias Tymeslot.Utils.DateTimeUtils

  alias Tymeslot.Emails.Shared.BookingRequestLocation
  alias Tymeslot.Meetings.MeetingSchema, as: Meeting

  use Gettext, backend: TymeslotWeb.Gettext

  # Amber rather than the confirmed brand colour: the band is the first thing
  # read, and it should not say "done".
  @intent :alert

  @spec render(Meeting.t(), keyword()) :: Swoosh.Email.t()
  def render(%Meeting{} = meeting, opts \\ []) do
    locale = RecipientLocale.attendee_locale(meeting)

    TemplateHelper.with_locale_and_tone(locale, meeting, fn ->
      # The stored title and texts are in the organiser's language; the booker
      # reads them in theirs (`AttendeeTexts`). The links are built now, not
      # read from the booking-time copy.
      meeting =
        meeting
        |> MeetingLinks.with_current_links()
        |> AttendeeTexts.attendee_view(locale)

      kind = if rescheduled?(meeting), do: :reschedule, else: :booking
      attendee_time = TimezoneHelper.convert_to_attendee_timezone(meeting)
      details = meeting_details(meeting, attendee_time)
      previous = previous_time_text(meeting, opts, locale)

      mjml_content = """
      #{Text.centered_text(intro(meeting, kind), padding: "8px 0 16px 0")}
      #{Text.section_title(requested_time_title(kind))}
      #{MeetingComponents.meeting_details_table(details, locale)}
      #{if previous, do: ~s(<mj-text font-size="14px" color="#{Styles.ink_muted()}" line-height="20px" padding="6px 0 0 0">#{Sanitise.sanitize_for_email(previous)}</mj-text>), else: ""}
      #{if RequestFields.request?(meeting), do: MeetingComponents.request_description_box(@intent, meeting.attendee_message), else: ""}

      <mj-text font-size="16px" color="#{Styles.ink_soft()}" line-height="24px" padding="16px 0">
        #{Sanitise.sanitize_for_email(waiting_sentence(meeting, locale))}
      </mj-text>

      <mj-text font-size="14px" color="#{Styles.ink_muted()}" line-height="20px" padding="8px 0 0 0">
        #{Sanitise.sanitize_for_email(held_sentence(meeting, kind))}
      </mj-text>

      #{cancel_line(meeting)}
      """

      html_body =
        TemplateHelper.compile_system_template(
          mjml_content,
          heading(kind),
          dgettext(
            "emails_booking_requests",
            "%{organizer} has received your request. The appointment is not booked yet.",
            organizer: meeting.organizer_name
          ),
          intent: @intent,
          # A request is not a booking: its foot says the guest requested it.
          audience: if(kind == :booking, do: :requester, else: :guest),
          # A neutral state, never a promise of the outcome (professor, 23.11.2026).
          eyebrow: dgettext("emails_booking_requests", "Request received"),
          stage_title: stage_title(kind),
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
        subject_line(kind, meeting, subject_date(meeting, details, attendee_time, locale))
      )
      |> html_body(html_body)
      |> text_body(text_body_for({meeting, kind}, details, previous, locale))
    end)
  end

  # Confirmed once already: the invitee is moving a meeting, not booking one.
  defp rescheduled?(%Meeting{first_announced_at: %DateTime{}}), do: true
  defp rescheduled?(_meeting), do: false

  defp heading(:booking),
    do: dgettext("emails_booking_requests", "Your request has been received.")

  defp heading(:reschedule),
    do: dgettext("emails_booking_requests", "Reschedule Request Received")

  defp stage_title(:booking), do: heading(:booking)
  defp stage_title(:reschedule), do: dgettext("emails_booking_requests", "Reschedule requested")

  defp requested_time_title(:booking), do: dgettext("emails_booking_requests", "Requested Time")

  defp requested_time_title(:reschedule),
    do: dgettext("emails_booking_requests", "Requested New Time")

  # The organiser writes in the first person, as in the confirmation.
  defp intro(meeting, kind),
    do:
      dgettext("emails_booking_requests", "Dear %{name},", name: meeting.attendee_name) <>
        "\n\n" <> text_intro(meeting, kind)

  defp text_intro(_meeting, :booking) do
    dgettext(
      "emails_booking_requests",
      "Thank you for your request. I review each request personally; the appointment is booked only once I confirm it."
    )
  end

  defp text_intro(_meeting, :reschedule) do
    dgettext(
      "emails_booking_requests",
      "Thank you for your request to move the appointment. I review each change personally; the new time applies only once I confirm it."
    )
  end

  defp held_sentence(_meeting, :booking) do
    dgettext(
      "emails_booking_requests",
      "If I confirm the request, you will receive the invitation with the Microsoft Teams link for your calendar."
    )
  end

  defp held_sentence(_meeting, :reschedule) do
    dgettext(
      "emails_booking_requests",
      "If I confirm the change, you will receive the updated invitation for your calendar."
    )
  end

  # A request with a title names date and time (rd-request-fields.patch),
  # as the other meeting emails' subjects do; the rest keeps the date.
  defp subject_date(meeting, details, attendee_time, locale) do
    if RequestFields.request?(meeting),
      do: TemplateHelper.subject_moment(details, locale),
      else: Formatting.format_date_short(attendee_time, locale)
  end

  defp subject_line(:booking, meeting, date) do
    case RequestFields.title(meeting) do
      nil ->
        dgettext("emails_booking_requests", "Request received: %{title} - %{date}",
          title: meeting.title,
          date: date
        )

      title ->
        dgettext("emails_booking_requests", "Your meeting request: %{title} on %{date}",
          title: title,
          date: date
        )
    end
  end

  defp subject_line(:reschedule, meeting, date) do
    dgettext("emails_booking_requests", "Reschedule requested: %{title} - %{date}",
      title: meeting.title,
      date: date
    )
  end

  defp previous_time_text(meeting, opts, locale) do
    case Keyword.get(opts, :previous_start_time) do
      %DateTime{} = previous ->
        dgettext("emails_booking_requests", "Previously scheduled for %{time}.",
          time:
            previous
            |> DateTimeUtils.convert_to_timezone(meeting.attendee_timezone || "UTC")
            |> Formatting.format_datetime(locale)
        )

      _unknown ->
        nil
    end
  end

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

  # Naming the deadline is what makes the wait tolerable. Where the request
  # has no deadline recorded we say nothing rather than inventing one, and
  # promise no reply time either way: what happens is what the system does.
  defp waiting_sentence(%Meeting{approval_deadline_at: nil}, _locale) do
    dgettext(
      "emails_booking_requests",
      "You will receive an email as soon as the request has been confirmed or declined."
    )
  end

  defp waiting_sentence(%Meeting{} = meeting, locale) do
    deadline =
      meeting.approval_deadline_at
      |> DateTimeUtils.convert_to_timezone(meeting.attendee_timezone || "UTC")
      |> Formatting.format_datetime(locale)

    dgettext(
      "emails_booking_requests",
      "The time is held for you until %{deadline}. If the request has not been confirmed by then, the time is released and you will receive an email.",
      deadline: deadline
    )
  end

  # The msgid carries no markup — the `<a>` is built here and passed in as
  # %{link}, so translators only ever see plain text and a placeholder, and
  # the href goes through the same URL validation every other link in these
  # templates gets before it reaches the sink.
  defp cancel_line(%Meeting{cancel_url: url}) do
    case Sanitise.sanitize_url(url) do
      nil -> ""
      safe_url -> withdraw_line(safe_url)
    end
  end

  defp withdraw_line(safe_url) do
    link_text =
      Sanitise.sanitize_for_email(dgettext("emails_booking_requests", "withdraw your request"))

    link_html =
      ~s(<a href="#{safe_url}" style="color:#{Styles.component_color(:link)}">#{link_text}</a>)

    """
    <mj-text font-size="14px" color="#{Styles.ink_muted()}" line-height="20px" padding="16px 0 0 0">
      #{dgettext("emails_booking_requests", "If you no longer need the appointment, you can %{link}.", link: link_html)}
    </mj-text>
    """
  end

  defp text_description(meeting) do
    if RequestFields.request?(meeting) and is_binary(meeting.attendee_message),
      do:
        "\n" <>
          dgettext("emails", "Request description") <> ":\n" <> meeting.attendee_message <> "\n",
      else: ""
  end

  defp text_body_for({meeting, kind}, details, previous, locale) do
    """
    #{heading(kind)}

    #{dgettext("emails_booking_requests", "Dear %{name},", name: meeting.attendee_name)}

    #{text_intro(meeting, kind)}

    #{dgettext("emails_booking_requests", "REQUESTED TIME:")}
    #{TextBodyHelper.format_meeting_details(details, locale)}
    #{previous || ""}#{text_description(meeting)}

    #{waiting_sentence(meeting, locale)}

    #{held_sentence(meeting, kind)}
    #{if Sanitise.safe_url?(meeting.cancel_url), do: "\n" <> dgettext("emails_booking_requests", "Withdraw your request:") <> "\n" <> meeting.cancel_url, else: ""}
    """
  end
end
