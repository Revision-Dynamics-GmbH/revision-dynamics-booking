defmodule Tymeslot.RdVisit do
  @moduledoc """
  On-site appointments booked directly on revisiondynamics.com (Revision
  Dynamics, `rd-visit-service.patch`).

  The website computes which 90-minute visits fit Tim's calendar by car (its
  own routing and address service, never a third party) and asks this module
  over the internal listener (`TymeslotWeb.RdVisitInternal`) for two things:

    * `busy/2`: the busy times of the host's calendars in a window, with the
      place of each one, so the website can drive from the appointment
      before. Exactly what the local prototype read (`visit-calendar.exs`):
      Outlook through Graph with the structured address, items marked
      "free" and cancelled ones left out; any other calendar through
      Tymeslot's own availability fetch; plus the host's live bookings,
      which may not have reached the calendar yet.
    * `book/1`: a visit at a time the website re-checked. It becomes an
      ordinary ad-hoc booking (`Tymeslot.Bookings.CreateAdHoc`) at the
      visit address, so Tymeslot writes the Outlook entry, sends the guest's
      confirmation and Tim's notice in the house design, reminds and lets
      the guest cancel. Anfahrt and Rückfahrt go into the same calendar as
      busy entries of their own, which `release_travel/1` removes again when
      the visit is cancelled or moved.

  The visit is host-managed in one respect only: its guest cannot move it on
  Tymeslot's page, which knows nothing about travel
  (`Tymeslot.Bookings.Policy.can_booker_move_meeting?/1`); cancelling stays
  open.

  Nothing here runs without `RD_VISIT_SECRET`.
  """

  alias Tymeslot.Availability
  alias Tymeslot.Bookings.Activation
  alias Tymeslot.Bookings.BookingTitle
  alias Tymeslot.Bookings.CreateAdHoc
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Infrastructure.Tasks
  alias Tymeslot.Integrations.Calendar.Events, as: CalendarEvents
  alias Tymeslot.Integrations.Calendar.HTTP
  alias Tymeslot.Integrations.Calendar.ICalBuilder
  alias Tymeslot.Integrations.Calendar.Management
  alias Tymeslot.Integrations.Calendar.Outlook.CalendarAPI
  alias Tymeslot.Integrations.Calendar.Outlook.Paging
  alias Tymeslot.Integrations.Calendar.Shared.MultiCalendarFetch
  alias Tymeslot.Integrations.Calendar.Tokens
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.RdVisit.Request
  alias Tymeslot.RdVisit.VisitQueries
  alias TymeslotWeb.Gettext, as: Translations

  require Logger

  @marker "rd_visit"
  @zone "Europe/Berlin"
  @max_window_days 14
  @live_statuses [:confirmed, :awaiting_approval, :awaiting_payment]
  @names %{
    {"humanos", "de"} => "HumanOS vor Ort",
    {"humanos", "en"} => "HumanOS on site",
    {"organisationos", "de"} => "OrganisationOS vor Ort",
    {"organisationos", "en"} => "OrganisationOS on site"
  }

  @type busy_event :: %{start: DateTime.t(), end: DateTime.t(), location: String.t() | nil}

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  @doc "The shared secret of the internal listener, or nil when it is off."
  @spec secret() :: String.t() | nil
  def secret do
    case System.get_env("RD_VISIT_SECRET") do
      value when is_binary(value) and byte_size(value) >= 32 -> value
      _missing_or_short -> nil
    end
  end

  @doc "The username of the host whose calendar the visits use."
  @spec host_username() :: String.t()
  def host_username, do: System.get_env("RD_VISIT_USERNAME") || "tim"

  @doc "Whether `meeting` is a visit booked through this module."
  @spec visit?(term()) :: boolean()
  def visit?(meeting) when is_map(meeting) do
    case Map.get(meeting, :tracking_params) do
      %{@marker => %{}} -> true
      _other -> false
    end
  end

  def visit?(_meeting), do: false

  @doc "The appointment's name for a product in a language."
  @spec appointment_name(String.t(), String.t()) :: String.t()
  def appointment_name(product, locale), do: Map.fetch!(@names, {product, locale})

  # ---------------------------------------------------------------------------
  # Busy times
  # ---------------------------------------------------------------------------

  @doc """
  The host's busy times overlapping `[from, to)` (dates in Berlin, `to`
  exclusive, at most #{@max_window_days} days), each with its place or nil.
  `{:error, :calendar}` when any calendar could not be read: the website then
  offers nothing rather than a time that might be taken.
  """
  @spec busy(Date.t(), Date.t()) :: {:ok, [busy_event()]} | {:error, atom()}
  def busy(%Date{} = from, %Date{} = to) do
    days = Date.diff(to, from)

    with true <- days > 0 and days <= @max_window_days,
         {:ok, user_id} <- host_user_id() do
      busy_for(user_id, start_of(from), start_of(to))
    else
      false -> {:error, :invalid}
      error -> error
    end
  end

  defp busy_for(user_id, start_at, end_at) do
    with {:ok, calendar} <- calendar_busy(user_id, start_at, end_at) do
      bookings =
        user_id
        |> Meetings.list_meetings_in_range_for_organizer(start_at, end_at)
        |> Enum.filter(&(&1.status in @live_statuses))
        |> Enum.map(&%{start: &1.start_time, end: &1.end_time, location: place(&1.location)})

      {:ok,
       (calendar ++ bookings)
       |> Enum.filter(&overlaps?(&1, start_at, end_at))
       |> Enum.uniq()
       |> Enum.sort_by(& &1.start, DateTime)}
    end
  end

  defp overlaps?(%{start: s, end: e}, from, to),
    do: DateTime.compare(s, to) == :lt and DateTime.compare(e, from) == :gt

  defp calendar_busy(user_id, start_at, end_at) do
    {outlook, other} =
      user_id
      |> Management.list_calendar_integrations()
      |> Enum.filter(& &1.is_active)
      |> Enum.split_with(&(&1.provider == "outlook"))

    with {:ok, from_outlook} <- outlook_busy(outlook, start_at, end_at),
         {:ok, from_other} <- other_busy(other, user_id, start_at, end_at) do
      {:ok, from_outlook ++ from_other}
    end
  end

  # As `visit-calendar.exs` read it: every calendar selected for conflict
  # checks, one after another (Graph allows four requests per mailbox at a
  # time), the structured address before the display name, and nothing that
  # is cancelled or shown as free.
  defp outlook_busy(integrations, start_at, end_at) do
    params = %{
      "startDateTime" => DateTime.to_iso8601(start_at),
      "endDateTime" => DateTime.to_iso8601(end_at),
      "$select" => "start,end,location,isCancelled,showAs",
      "$top" => "500"
    }

    Enum.reduce_while(integrations, {:ok, []}, fn integration, {:ok, acc} ->
      case outlook_events(integration, params) do
        {:ok, events} -> {:cont, {:ok, acc ++ events}}
        _failed -> {:halt, {:error, :calendar}}
      end
    end)
  end

  defp outlook_events(integration, params) do
    calendars = MultiCalendarFetch.get_selected_calendars(integration)

    Tokens.with_access_token(integration, &CalendarAPI.refresh_token/1, fn token ->
      Enum.reduce_while(calendars, {:ok, []}, fn calendar, {:ok, acc} ->
        path = "/me/calendars/#{HTTP.segment(calendar.id)}/calendarView"

        case Paging.list_all(token, path, params) do
          {:ok, events} -> {:cont, {:ok, acc ++ Enum.flat_map(events, &outlook_busy_event/1)}}
          _failed -> {:halt, {:error, :calendar}}
        end
      end)
    end)
  rescue
    error ->
      Logger.warning("rd_visit: Outlook read failed", reason: LogFormat.reason(error))
      {:error, :calendar}
  end

  defp outlook_busy_event(%{"isCancelled" => true}), do: []
  defp outlook_busy_event(%{"showAs" => "free"}), do: []

  defp outlook_busy_event(%{"start" => %{"dateTime" => s}, "end" => %{"dateTime" => e}} = event) do
    with {:ok, start_at} <- graph_time(s), {:ok, end_at} <- graph_time(e) do
      [%{start: start_at, end: end_at, location: outlook_place(event["location"])}]
    else
      _bad -> []
    end
  end

  defp outlook_busy_event(_event), do: []

  # Graph answers in UTC without a zone suffix ("2026-11-24T09:00:00.0000000").
  defp graph_time(value) when is_binary(value) do
    case DateTime.from_iso8601(if String.ends_with?(value, "Z"), do: value, else: value <> "Z") do
      {:ok, at, _offset} -> {:ok, DateTime.truncate(at, :second)}
      error -> error
    end
  end

  defp outlook_place(%{} = location) do
    address = location["address"] || %{}

    physical =
      [address["street"], address["postalCode"], address["city"]]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    if physical != "", do: physical, else: place(location["displayName"])
  end

  defp outlook_place(_location), do: nil

  # A place the car can drive to: not an online meeting room or a link.
  defp place(value) when is_binary(value) do
    text = String.trim(value)
    if text == "" or Regex.match?(~r/teams|zoom|online|https?:/i, text), do: nil, else: text
  end

  defp place(_value), do: nil

  defp other_busy([], _user_id, _start_at, _end_at), do: {:ok, []}

  defp other_busy(_integrations, user_id, start_at, end_at) do
    case CalendarEvents.get_events_for_range_fresh(
           user_id,
           DateTime.to_date(start_at),
           DateTime.to_date(end_at)
         ) do
      {:ok, events} -> {:ok, Enum.flat_map(events, &other_busy_event/1)}
      _unreadable -> {:error, :calendar}
    end
  end

  defp other_busy_event(event) do
    with false <- free?(event),
         %DateTime{} = s <- time(event[:start_time]),
         %DateTime{} = e <- time(event[:end_time]) do
      [%{start: s, end: e, location: place(event[:location])}]
    else
      _free_or_untimed -> []
    end
  end

  defp free?(event) do
    event[:transparency] in ["transparent", :transparent] or event[:show_as] == "free" or
      event[:status] in ["cancelled", :cancelled]
  end

  defp time(%DateTime{} = at), do: DateTime.truncate(at, :second)

  defp time(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

  defp time(_other), do: nil

  defp start_of(%Date{} = date),
    do: date |> DateTime.new!(~T[00:00:00], @zone) |> DateTime.shift_zone!("Etc/UTC")

  # ---------------------------------------------------------------------------
  # Booking
  # ---------------------------------------------------------------------------

  @doc """
  Books a visit from the website's request (`Tymeslot.RdVisit.Request`).

  The whole window from the first departure to the last arrival must still be
  free in the calendar, and the visit itself free among Tymeslot's bookings;
  otherwise `{:error, :taken}`. Visits are booked one at a time.
  """
  @spec book(map()) :: {:ok, MeetingSchema.t()} | {:error, atom()}
  def book(params) do
    with {:ok, request} <- Request.parse(params),
         {:ok, user_id} <- host_user_id(),
         {:ok, meeting, pending} <- create(user_id, request) do
      :ok = Activation.after_commit(pending)
      meeting = write_travel(meeting, user_id, request.travel)
      Availability.changed(user_id)
      {:ok, meeting}
    end
  end

  defp host_user_id do
    case ProfileQueries.get_by_username(host_username()) do
      {:ok, profile} -> {:ok, profile.user_id}
      _missing -> {:error, :host}
    end
  end

  defp create(user_id, request) do
    window = window(request)

    result =
      VisitQueries.transaction(
        fn ->
          VisitQueries.lock_bookings()

          case create_locked(user_id, request, window) do
            {:ok, meeting, pending} -> {meeting, pending}
            {:error, :time_conflict} -> VisitQueries.rollback(:taken)
            {:error, reason} when is_atom(reason) -> VisitQueries.rollback(reason)
            _other -> VisitQueries.rollback(:failed)
          end
        end,
        timeout: 60_000
      )

    case result do
      {:ok, {meeting, pending}} -> {:ok, meeting, pending}
      {:error, reason} -> {:error, reason}
    end
  end

  # From the first departure to the last arrival.
  defp window(request) do
    starts = [request.start | Enum.map(request.travel, & &1.start)]
    ends = [request.end | Enum.map(request.travel, & &1.end)]
    {Enum.min(starts, DateTime), Enum.max(ends, DateTime)}
  end

  defp create_locked(user_id, request, {window_start, window_end}) do
    appointment = appointment_name(request.product, request.locale)

    with {:ok, []} <- busy_for(user_id, window_start, window_end),
         {:ok, meeting, pending} <-
           CreateAdHoc.execute_deferred(ad_hoc_params(user_id, request, appointment)),
         {:ok, meeting} <- mark(meeting, request, appointment) do
      {:ok, meeting, pending}
    else
      {:ok, [_first | _rest]} -> {:error, :taken}
      other -> other
    end
  end

  defp ad_hoc_params(user_id, request, appointment) do
    {integration_id, calendar_path} =
      case CalendarEvents.get_booking_integration_info(user_id) do
        {:ok, %{integration_id: id, calendar_path: path}} -> {id, path}
        _none -> {nil, nil}
      end

    %{
      title: appointment,
      start_time: request.start,
      end_time: request.end,
      attendee_name: request.name,
      attendee_email: request.email,
      attendee_timezone: @zone,
      attendee_locale: request.locale,
      organizer_user_id: user_id,
      calendar_integration_id: integration_id,
      calendar_path: calendar_path,
      video_integration_id: nil,
      location: {:custom, request.address},
      reminders: [%{value: 1, unit: "days"}]
    }
  end

  # Named like an online booking: "<appointment> x <institution>" on Tim's
  # side, "<appointment> with <name>" in the guest's language on theirs
  # (`BookingTitle`). The marker lets the policy, the links and the clean-up
  # recognise the visit; utm says where it came from in the dashboard.
  defp mark(meeting, request, appointment) do
    title =
      Gettext.with_locale(Translations, "de", fn ->
        BookingTitle.organiser_title(appointment, request.name, request.institution)
      end)

    VisitQueries.update_meeting(meeting, %{
      title: title,
      summary: title,
      meeting_type: appointment,
      attendee_company: request.institution,
      utm_source: "revisiondynamics.com",
      utm_medium: "vor-ort",
      tracking_params: Map.put(meeting.tracking_params || %{}, @marker, %{"travel" => []})
    })
  end

  # Anfahrt and Rückfahrt as busy entries of their own in the visit's calendar.
  # A calendar that refuses one leaves the visit booked: it is in the
  # calendar already, and the log says which drive is missing.
  defp write_travel(meeting, _user_id, []), do: meeting

  defp write_travel(%MeetingSchema{calendar_integration_id: nil} = meeting, _user_id, _travel),
    do: meeting

  defp write_travel(meeting, user_id, travel) do
    written =
      travel
      |> Enum.with_index()
      |> Enum.flat_map(fn {entry, index} ->
        write_travel_entry(meeting, user_id, entry, index)
      end)

    params = put_in(meeting.tracking_params, [@marker, "travel"], written)

    case VisitQueries.update_meeting(meeting, %{tracking_params: params}) do
      {:ok, updated} -> updated
      {:error, _changeset} -> meeting
    end
  end

  defp write_travel_entry(meeting, user_id, entry, index) do
    # Written like an event made on the dashboard calendar
    # (`Tymeslot.CalendarGrid.EventCreation`): its own iCal UID, no guests,
    # busy, and not marked as Tymeslot's own, so a sync reads it back as an
    # ordinary busy entry rather than a booking that lost its meeting.
    data = %{
      uid: ICalBuilder.generate_uid(),
      calendar_integration_id: meeting.calendar_integration_id,
      summary: entry.title,
      description: entry.description,
      start_time: entry.start,
      end_time: entry.end,
      calendar_id: meeting.calendar_path,
      show_as: "busy",
      transparency: "opaque",
      reminders: [],
      attendees: [],
      created_by_tymeslot: false,
      creation_key: "rd-visit-#{meeting.uid}-#{index}"
    }

    case CalendarEvents.create_event(data, {meeting.calendar_integration_id, user_id}) do
      {:ok, created} ->
        [
          %{
            "uid" => created.uid,
            "provider_event_id" => created.provider_event_id,
            "integration_id" => meeting.calendar_integration_id
          }
        ]

      {:error, reason} ->
        travel_not_written(meeting, reason)
    end
  rescue
    # The visit is booked and its emails are out: a calendar that fails here
    # costs the drive entry, never the booking's answer.
    error -> travel_not_written(meeting, error)
  end

  defp travel_not_written(meeting, reason) do
    Logger.warning("rd_visit: travel entry not written",
      meeting_id: meeting.id,
      reason: LogFormat.reason(reason)
    )

    []
  end

  # ---------------------------------------------------------------------------
  # Clean-up
  # ---------------------------------------------------------------------------

  @doc """
  Removes the travel entries of a visit that was cancelled or moved, in the
  background. Any other meeting is left alone.
  """
  @spec release_travel(term()) :: :ok
  def release_travel(meeting) do
    if visit?(meeting) do
      Tasks.start_child(Tymeslot.TaskSupervisor, fn -> release_now(meeting) end)
    end

    :ok
  end

  defp release_now(%{id: id}) when is_binary(id) or is_integer(id) do
    with %MeetingSchema{} = meeting <- VisitQueries.get_meeting(id),
         %{@marker => %{"travel" => [_first | _rest] = travel}} <- meeting.tracking_params do
      left = Enum.reject(travel, &deleted?(&1, meeting.organizer_user_id))
      params = put_in(meeting.tracking_params, [@marker, "travel"], left)
      VisitQueries.update_meeting(meeting, %{tracking_params: params})
      Availability.changed(meeting.organizer_user_id)
    end

    :ok
  rescue
    error ->
      Logger.warning("rd_visit: travel entries not removed", reason: LogFormat.reason(error))
      :ok
  end

  defp release_now(_meeting), do: :ok

  defp deleted?(entry, user_id) do
    opts =
      if entry["provider_event_id"],
        do: [provider_event_id: entry["provider_event_id"]],
        else: []

    case CalendarEvents.delete_event(entry["uid"], {entry["integration_id"], user_id}, opts) do
      :ok -> true
      {:ok, _result} -> true
      {:error, :not_found} -> true
      _failed -> false
    end
  end
end
