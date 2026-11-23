defmodule Tymeslot.RdVisit.VisitQueries do
  @moduledoc """
  The database calls of on-site visits (`Tymeslot.RdVisit`): the lock that
  books visits one at a time, and the visit's own fields on its meeting.
  """

  alias Ecto.Changeset
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo

  @doc """
  Takes the transaction-scoped lock all visit bookings share, so a check of
  the calendar and the booking it allows never interleave with another
  visit's. Call inside `Repo.transaction/2`; it is released at commit.
  """
  @spec lock_bookings() :: :ok
  def lock_bookings do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('rd_visit_booking'))")
    :ok
  end

  @doc "Runs `fun` in a transaction, as `Repo.transaction/2`."
  @spec transaction((-> term()), keyword()) :: {:ok, term()} | {:error, term()}
  def transaction(fun, opts \\ []), do: Repo.transaction(fun, opts)

  @doc "Aborts the transaction `transaction/2` runs, as `Repo.rollback/1`."
  @spec rollback(term()) :: no_return()
  def rollback(reason), do: Repo.rollback(reason)

  @doc "The meeting with this id, or nil."
  @spec get_meeting(term()) :: MeetingSchema.t() | nil
  def get_meeting(id), do: Repo.get(MeetingSchema, id)

  @doc """
  Writes the visit's fields on its meeting: its titles, the institution, where
  it came from and the visit marker in `tracking_params`. Only these fields
  change.
  """
  @spec update_meeting(MeetingSchema.t(), map()) ::
          {:ok, MeetingSchema.t()} | {:error, Changeset.t()}
  def update_meeting(%MeetingSchema{} = meeting, attrs) do
    meeting
    |> Changeset.change(
      Map.take(attrs, [
        :title,
        :summary,
        :meeting_type,
        :attendee_company,
        :utm_source,
        :utm_medium,
        :tracking_params
      ])
    )
    |> Repo.update()
  end
end
