defmodule TymeslotWeb.Live.Scheduling.RequestFieldsTest do
  @moduledoc """
  A booking request with its title and description (Revision Dynamics,
  rd-request-fields.patch), end to end on the Paper theme the instance uses:
  the form asks for both and refuses a request without them; the request
  holds the slot, names the host's calendar entry "<title> x <institution>",
  carries the description into the calendar entry and both emails; the host
  approves or declines from the link in the request email, and the booker is
  told in the emails of this patch.

  The fields are off for the suite (`config/test.exs`); these tests turn them
  on, which is global application env: not async. Mocked are the boundaries
  only, the calendar provider among them; emails go through the real email
  service into Swoosh's test adapter.
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :bookings

  import Mox
  import Tymeslot.BookingTestHelpers, only: [seed_booking_account: 3]
  import Tymeslot.ConfigTestHelpers

  alias Ecto.Changeset
  alias Tymeslot.Infrastructure.AvailabilityCache
  alias Tymeslot.Integrations.Calendar.CalendarEventBuilder
  alias Tymeslot.Integrations.Calendar.CreatedEvent
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.MeetingTypes.MeetingTypeSchema
  alias Tymeslot.Repo
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.TestMocks
  alias TymeslotWeb.BookingDriver

  @timezone "Europe/Berlin"
  @queues [:calendar_events, :video_rooms, :emails]
  @title "form[data-fact='attendee'] input[name='booking[title]']"
  @description "form[data-fact='attendee'] textarea[name='booking[message]']"
  @company "form[data-fact='attendee'] input[name='booking[company]']"

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)
    RateLimiter.clear_all()
    AvailabilityCache.clear_all()
    TestMocks.setup_subscription_mocks()
    with_config(:tymeslot, booking_request_fields: true, booking_institution_field: true)

    recaptcha = Application.get_env(:tymeslot, :recaptcha, [])
    Application.put_env(:tymeslot, :recaptcha, Keyword.put(recaptcha, :booking_enabled, false))
    email_service = Application.get_env(:tymeslot, :email_service_module)
    Application.put_env(:tymeslot, :email_service_module, Tymeslot.Emails.EmailService)
    Application.put_env(:swoosh, :shared_test_process, self())

    on_exit(fn ->
      Application.put_env(:tymeslot, :recaptcha, recaptcha)
      Application.put_env(:tymeslot, :email_service_module, email_service)
      Application.delete_env(:swoosh, :shared_test_process)
    end)

    test_pid = self()

    Tymeslot.CalendarMock
    |> stub(:get_events_for_range_fresh, fn _user_id, _start, _end -> {:ok, []} end)
    |> stub(:get_booking_integration_info, fn _context -> {:error, :no_integration} end)
    |> stub(:create_event, fn event_data, _context ->
      send(test_pid, {:calendar_create, event_data})
      {:ok, CreatedEvent.new("request-event-uid")}
    end)
    |> stub(:update_event, fn _uid, event_data, _context ->
      send(test_pid, {:calendar_update, event_data.status})
      :ok
    end)
    |> stub(:delete_event, fn _uid, _context, _opts -> :ok end)

    %{user: user, profile: profile} = seed_booking_account("3", "request-#{tags.line}", @timezone)

    meeting_type =
      MeetingTypeSchema
      |> Repo.get_by!(user_id: user.id)
      |> Changeset.change(
        name: "Individueller Termin",
        requires_approval: true,
        approval_window_hours: 48,
        is_private: false,
        duration_minutes: 30,
        extra_lengths_minutes: [45, 60, 75, 90, 105, 120]
      )
      |> Repo.update!()

    %{user: user, profile: profile, meeting_type: meeting_type}
  end

  @tag :capture_log
  test "the form asks for a title and a description, the institution is optional",
       %{conn: conn, user: user, profile: profile} do
    view = open_form(conn, profile, 60)

    assert has_element?(view, "#{@title}[required][maxlength='120']")
    assert has_element?(view, "#{@description}[required][maxlength='2000']")
    assert has_element?(view, @company)
    refute has_element?(view, "#{@company}[required]")

    html = render(view)
    assert html =~ "Title"
    assert html =~ "Description"
    assert html =~ "Institution or company (optional)"
    # The hold names its limit, the type's 48-hour window (professor, 23.11.2026).
    assert html =~ "for up to 48 hours"

    # Without them nothing is requested, and the form says why.
    refused =
      BookingDriver.submit(view, %{
        name: "Max Mustermann",
        email: "max@example.com",
        company: "",
        title: " ",
        message: " \n "
      })

    assert refused =~ "Please enter a title."
    assert refused =~ "Please describe briefly what it is about."
    refute Repo.get_by(MeetingSchema, organizer_user_id: user.id)
  end

  @tag :capture_log
  test "a request is held, titled for the host, and approved from the email",
       %{conn: conn, user: user, profile: profile} do
    view = open_form(conn, profile, 60)

    BookingDriver.submit(view, %{
      name: "Max Mustermann",
      email: "max@example.com",
      company: "Montessori-Schule Idstein",
      title: "Abstimmung\n Pilotphase",
      message: "Wir möchten die Einführung im Kollegium besprechen."
    })

    meeting = Repo.get_by!(MeetingSchema, organizer_user_id: user.id)
    assert meeting.status == :awaiting_approval
    assert meeting.duration == 60
    assert meeting.title == "Abstimmung Pilotphase x Montessori-Schule Idstein"
    assert meeting.summary == meeting.title
    assert meeting.attendee_company == "Montessori-Schule Idstein"
    assert meeting.attendee_message == "Wir möchten die Einführung im Kollegium besprechen."
    assert meeting.custom_field_answers == %{"rd_request_title" => "Abstimmung Pilotphase"}

    # The host's calendar holds the request, with its title and description.
    drain()
    assert_receive {:calendar_create, %{status: :tentative} = event}
    assert event.summary == "Abstimmung Pilotphase x Montessori-Schule Idstein"
    assert event.description =~ "Title: Abstimmung Pilotphase"
    assert event.description =~ "Description:\nWir möchten die Einführung"
    assert CalendarEventBuilder.build_event_description(meeting) =~ "Title: Abstimmung Pilotphase"

    emails = drain_mailbox()

    to_host = email_to(emails, user.email)
    assert to_host.subject =~ "Meeting request: Abstimmung Pilotphase (Max Mustermann)"
    assert to_host.html_body =~ "Abstimmung Pilotphase"
    assert to_host.html_body =~ "Wir möchten die Einführung im Kollegium besprechen."
    assert to_host.html_body =~ "Montessori-Schule Idstein"
    assert to_host.text_body =~ "Title: Abstimmung Pilotphase"
    assert to_host.text_body =~ "Description:\nWir möchten die Einführung"
    assert to_host.html_body =~ "Approve"
    assert to_host.html_body =~ "Decline"

    to_booker = email_to(emails, "max@example.com")
    assert to_booker.subject =~ "Your meeting request: Abstimmung Pilotphase on"
    assert to_booker.html_body =~ "Your request has been received."
    assert to_booker.html_body =~ "Request received"
    assert to_booker.html_body =~ "Thank you for your request. I review each request personally"
    assert to_booker.text_body =~ "because you requested an appointment"
    refute to_booker.text_body =~ "because you booked an appointment"
    assert to_booker.html_body =~ "Wir möchten die Einführung im Kollegium besprechen."
    assert to_booker.text_body =~ "Dear Max Mustermann,"
    refute to_booker.html_body =~ "x Montessori-Schule Idstein"
    assert to_booker.attachments == []

    [_match, token] = Regex.run(~r{/meeting-request/([^"'\s<]+)}, to_host.html_body)
    {:ok, request_view, _html} = live(build_conn(), "/meeting-request/#{token}")
    request_view |> element("[data-testid='approve-request']") |> render_click()
    drain()

    assert Repo.reload!(meeting).status == :confirmed
    assert_received {:calendar_update, :confirmed}

    after_approval = drain_mailbox()
    confirmation = email_to(after_approval, "max@example.com")
    # No "New booking" email to the host who has just approved it himself.
    refute Enum.any?(after_approval, fn email ->
             Enum.any?(email.to, &match?({_, address} when address == user.email, &1))
           end)

    assert confirmation.subject =~ ~r/confirmed/i
    assert confirmation.text_body =~ "booked an appointment"
    assert confirmation.html_body =~ "I have confirmed your request."
    assert confirmation.html_body =~ "Abstimmung Pilotphase"
    refute confirmation.html_body =~ "x Montessori-Schule Idstein"
  end

  @tag :capture_log
  test "a request without an institution names the person, and a decline tells the booker",
       %{conn: conn, user: user, profile: profile} do
    view = open_form(conn, profile, 30)

    BookingDriver.submit(view, %{
      name: "Erika Musterfrau",
      email: "erika@example.com",
      company: "",
      title: "Frage zur Lizenz",
      message: "Kurze Frage zu den Lizenzen."
    })

    meeting = Repo.get_by!(MeetingSchema, organizer_user_id: user.id)
    assert meeting.title == "Frage zur Lizenz x Erika Musterfrau"
    assert meeting.attendee_company == nil
    assert meeting.duration == 30

    drain()
    to_host = email_to(drain_mailbox(), user.email)
    [_match, token] = Regex.run(~r{/meeting-request/([^"'\s<]+)}, to_host.html_body)

    {:ok, request_view, _html} = live(build_conn(), "/meeting-request/#{token}")

    # The host's page shows what was asked for before they answer.
    assert request_view |> element("[data-testid='request-title']") |> render() =~
             "Frage zur Lizenz"

    assert render(request_view) =~ "Kurze Frage zu den Lizenzen."

    request_view |> element("button[phx-value-intent='decline']") |> render_click()

    request_view
    |> form("#decline-request-form", %{reason: "Dazu passt ein anderer Termin besser."})
    |> render_submit()

    drain()

    assert Repo.reload!(meeting).status == :cancelled

    declined = email_to(drain_mailbox(), "erika@example.com")
    assert declined.subject =~ "Not confirmed: Frage zur Lizenz on"
    assert declined.html_body =~ "Unfortunately, I cannot confirm your request."
    assert declined.html_body =~ "Frage zur Lizenz"
    assert declined.html_body =~ "Dazu passt ein anderer Termin besser."
    assert declined.html_body =~ "Note from"
    assert declined.text_body =~ "because you requested an appointment"
    assert declined.html_body =~ "https://revisiondynamics.com/en/termine/individuell"

    assert declined.text_body =~
             "Request a new appointment: https://revisiondynamics.com/en/termine/individuell"
  end

  @tag :capture_log
  test "a type without requests keeps its form", %{
    conn: conn,
    profile: profile,
    meeting_type: type
  } do
    type
    |> Changeset.change(requires_approval: false, extra_lengths_minutes: [])
    |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/#{profile.username}?timezone=#{@timezone}")
    BookingDriver.book(view, until: :attendee)

    refute has_element?(view, @title)
    assert has_element?(view, "#{@company}[required]")
    refute has_element?(view, "#{@description}[required]")
  end

  defp open_form(conn, profile, minutes) do
    {:ok, view, _html} =
      live(
        conn,
        ~p"/#{profile.username}/individueller-termin?timezone=#{@timezone}&minutes=#{minutes}"
      )

    BookingDriver.book(view, until: :attendee)
    view
  end

  defp drain do
    ran =
      Enum.reduce(@queues, 0, fn queue, acc ->
        %{success: success, failure: failure} =
          Oban.drain_queue(queue: queue, with_recursion: true)

        assert failure == 0, "a #{queue} job failed"
        acc + success
      end)

    if ran > 0, do: drain()
  end

  defp email_to(emails, address) do
    case Enum.find(emails, fn email -> Enum.any?(email.to, &match?({_, ^address}, &1)) end) do
      nil -> flunk("no email to #{address}; received: #{inspect(Enum.map(emails, & &1.to))}")
      email -> email
    end
  end

  defp drain_mailbox(acc \\ []) do
    receive do
      {:email, email} -> drain_mailbox([email | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
