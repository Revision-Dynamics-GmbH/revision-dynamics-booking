defmodule Tymeslot.Meetings.AttendeeDecline do
  @moduledoc """
  Revision Dynamics (26.11.2026): an attendee who declines the calendar
  invitation cancels the booking.

  Tymeslot learns about a booking's provider event through the calendar sync.
  When the host deletes the event, `ExternalCalendarChanges` cancels the
  meeting. When the booked person declines the invitation in their own
  calendar, the host's copy of the event only records the reply; upstream
  Tymeslot ignored it, so the meeting stayed confirmed, the host received a
  reminder and the slot stayed blocked.

  Here a decline by the meeting's own attendee runs the same cancellation as
  the cancel link in the confirmation email (`Tymeslot.Bookings.Cancel.execute/1`):
  the meeting is cancelled, the event is removed from the host's calendar,
  reminders are dropped and both sides receive the cancellation email.

  Only solo meetings that are confirmed and still lie ahead are touched; a
  decline by anyone other than the booked attendee changes nothing.
  """

  require Logger

  alias Tymeslot.Bookings.Cancel
  alias Tymeslot.Integrations.Calendar.Attendee
  alias Tymeslot.Meetings.MeetingState

  @doc "Whether the booked attendee of `meeting` declined `calendar_event`."
  @spec declined?(map(), map()) :: boolean()
  def declined?(%{attendee_email: email} = meeting, %{attendees: attendees})
      when is_binary(email) and is_list(attendees) do
    target = normalise_email(email)

    target != "" and
      target != normalise_email(Map.get(meeting, :organizer_email)) and
      Enum.any?(attendees, fn attendee ->
        attendee = Attendee.normalise(attendee)
        normalise_email(attendee.email) == target and attendee.response_status == :declined
      end)
  end

  def declined?(_meeting, _calendar_event), do: false

  @doc """
  Cancels `meeting` because its attendee declined the invitation. Returns
  `:ok` when there is nothing to do or the meeting was cancelled.
  """
  @spec apply(map()) :: :ok | {:error, term()}
  def apply(%{status: _} = meeting) do
    cond do
      meeting.status != :confirmed -> :ok
      (Map.get(meeting, :capacity) || 1) > 1 -> :ok
      not MeetingState.expects_calendar_event?(meeting) -> :ok
      elapsed?(meeting) -> :ok
      true -> cancel(meeting)
    end
  end

  defp cancel(meeting) do
    case Cancel.execute(meeting) do
      {:ok, _cancelled} ->
        Logger.info("Meeting cancelled: attendee declined the calendar invitation",
          meeting_id: meeting.id
        )

        :ok

      {:error, :already_cancelled} ->
        :ok

      {:error, reason} ->
        Logger.warning("Cancelling a declined meeting failed; the next sync retries",
          meeting_id: meeting.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp elapsed?(%{end_time: %DateTime{} = end_time}),
    do: DateTime.before?(end_time, DateTime.utc_now())

  defp elapsed?(_meeting), do: false

  defp normalise_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalise_email(_email), do: ""
end
