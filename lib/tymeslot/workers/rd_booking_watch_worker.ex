defmodule Tymeslot.Workers.RdBookingWatchWorker do
  @moduledoc """
  Revision Dynamics (26.11.2026): checks every upcoming confirmed booking
  against its Outlook event directly, every five minutes.

  Tymeslot normally learns about calendar changes from Graph webhooks and the
  `calendarView/delta` feed. In production that feed stopped reporting
  changes (a booking created and deleted in Outlook never reached the cache),
  so an event Tim deleted, or an invitation the guest declined, left the
  booking confirmed: the guest kept their links, Tim got the reminder and the
  slot stayed blocked.

  This worker does not depend on the feed. For each confirmed booking still
  ahead it reads the one event by id:

    * gone (404) or cancelled in Outlook: handled like an external deletion
      (`ExternalCalendar.apply_external_calendar_change/5` with `:deleted`):
      the booking is cancelled and both sides get the cancellation email;
    * the booked guest declined the invitation: `AttendeeDecline.apply/1`
      cancels the booking like the cancel link does, which also removes the
      event from Tim's calendar.

  A booking with a calendar write of Tymeslot's own still queued is skipped
  until the next run, so a reschedule in flight is never mistaken for a
  deletion. Any other Graph error skips the booking for this run.
  """

  use Oban.Worker,
    queue: :calendar_events,
    max_attempts: 1,
    unique: [period: 240, states: [:available, :scheduled, :executing]]

  import Ecto.Query

  require Logger

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema
  alias Tymeslot.Integrations.Calendar.Outlook.CalendarAPI
  alias Tymeslot.Jobs
  alias Tymeslot.Meetings.AttendeeDecline
  alias Tymeslot.Meetings.ExternalCalendar
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo
  alias Tymeslot.Workers.CalendarEventWorker

  @horizon_days 180

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    meetings =
      Repo.all(
        from(m in MeetingSchema,
          where:
            m.status == :confirmed and not is_nil(m.provider_event_id) and
              not is_nil(m.calendar_integration_id) and m.end_time > ^now and
              m.start_time < ^DateTime.add(now, @horizon_days * 86_400, :second)
        )
      )

    integrations =
      meetings
      |> Enum.map(& &1.calendar_integration_id)
      |> Enum.uniq()
      |> then(&Repo.all(from(i in CalendarIntegrationSchema, where: i.id in ^&1)))
      |> Map.new(&{&1.id, &1})

    Enum.each(meetings, fn meeting ->
      case Map.get(integrations, meeting.calendar_integration_id) do
        %CalendarIntegrationSchema{provider: "outlook", is_active: true} = integration ->
          check(meeting, integration)

        _other ->
          :ok
      end
    end)

    :ok
  end

  defp check(meeting, integration) do
    if Jobs.pending_meeting_job?(CalendarEventWorker, meeting.id) do
      :ok
    else
      meeting
      |> read_event(integration)
      |> act(meeting, integration)
    end
  rescue
    error ->
      Logger.warning("Booking watch failed for one meeting",
        meeting_id: meeting.id,
        error: Exception.message(error)
      )

      :ok
  end

  defp read_event(meeting, integration),
    do: CalendarAPI.get_event(integration, meeting.provider_event_id)

  defp act({:error, :not_found, _message}, meeting, integration), do: deleted(meeting, integration)

  defp act({:ok, %{"isCancelled" => true}}, meeting, integration), do: deleted(meeting, integration)

  defp act({:ok, %{} = event}, meeting, _integration) do
    if AttendeeDecline.declined?(meeting, %{attendees: attendees(event)}) do
      Logger.info("Booking watch: guest declined the invitation", meeting_id: meeting.id)
      AttendeeDecline.apply(meeting)
    else
      :ok
    end
  end

  defp act(_other, _meeting, _integration), do: :ok

  defp deleted(meeting, integration) do
    Logger.info("Booking watch: Outlook event is gone", meeting_id: meeting.id)

    ExternalCalendar.apply_external_calendar_change(
      integration.id,
      meeting.provider_event_id,
      meeting.calendar_uid,
      :deleted
    )
  end

  defp attendees(%{"attendees" => attendees}) when is_list(attendees) do
    Enum.map(attendees, fn attendee ->
      %{
        email: get_in(attendee, ["emailAddress", "address"]),
        response_status:
          if(get_in(attendee, ["status", "response"]) == "declined", do: :declined, else: nil)
      }
    end)
  end

  defp attendees(_event), do: []
end
