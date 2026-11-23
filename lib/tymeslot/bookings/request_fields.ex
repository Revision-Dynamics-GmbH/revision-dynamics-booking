defmodule Tymeslot.Bookings.RequestFields do
  @moduledoc """
  Title and description of a booking request (Revision Dynamics,
  `rd-request-fields.patch`).

  A meeting type whose bookings the host has to approve
  (`requires_approval`, `Tymeslot.Meetings.Approval`) is a request for a
  conversation about the booker's own topic, such as Revision Dynamics'
  "Individueller Termin". Its booking form therefore asks for two things
  more, both required and checked on the server
  (`TymeslotWeb.Live.Scheduling.BookingConfig.booking_field_spec/1`):

    * the **title** (at most `title_max_length/0` characters, one line), and
    * the **description** (at most `description_max_length/0` characters),
      which is the form's message field under another label, kept where the
      message always was, in `attendee_message`.

  The institution or company (`Tymeslot.Bookings.Institution`) is optional
  on such a type.

  The title has no column of its own, so no migration is needed: it is kept
  in the meeting's `custom_field_answers` under the reserved key
  `answer_key/0`, which no custom question can have (theirs are UUIDs), and
  which every reader of custom answers ignores, as they only read the
  answers of the questions in `custom_fields_snapshot`. It is therefore
  erased with the rest of the invitee's data
  (`Tymeslot.InviteeData.InviteeDataQueries` empties the map).

  The title names the organiser's calendar entry, Teams meeting and dashboard
  entry, "<title> x <institution>", or "<title> x <name>" without an
  institution (`organiser_title/3`), and it heads the request email to the
  host. The booker and their guests keep reading the meeting as
  "<meeting type> with <name>" (`Tymeslot.Bookings.BookingTitle.localise/1`).

  The fields are on unless `config :tymeslot, :booking_request_fields` is
  `false`. The test suite turns them off (`config/test.exs`), as its
  approval tests book with a name, an email and a message only; the tests of
  the fields turn them on.
  """

  alias Tymeslot.Bookings.Institution
  alias Tymeslot.Meetings.Approval

  @title_max_length 120
  @description_max_length 2000
  @answer_key "rd_request_title"

  @doc "Whether request types ask for a title and a description at all."
  @spec field_enabled?() :: boolean()
  def field_enabled?,
    do: Application.get_env(:tymeslot, :booking_request_fields, true) != false

  @doc """
  Whether the booking form of `meeting_type` asks for a title and a
  description: the fields are on, and the type holds its bookings for the
  host's approval. A group type never does; its seats share one meeting.
  """
  @spec applies?(map() | nil) :: boolean()
  def applies?(meeting_type),
    do: field_enabled?() and Approval.required?(meeting_type) and not group?(meeting_type)

  @doc "The most characters a title may have, after `normalise_title/1`."
  @spec title_max_length() :: pos_integer()
  def title_max_length, do: @title_max_length

  @doc "The most characters a description may have, ends trimmed."
  @spec description_max_length() :: pos_integer()
  def description_max_length, do: @description_max_length

  @doc "The key the title is kept under in `custom_field_answers`."
  @spec answer_key() :: String.t()
  def answer_key, do: @answer_key

  @doc """
  The title as it is stored and shown: one line, as
  `Tymeslot.Bookings.Institution.normalise/1` makes it (control characters
  and line breaks become spaces, invisible format characters go, runs of
  whitespace become one space, the ends are trimmed). `nil` when blank or not
  text. It does not shorten; the form's validation refuses a longer one.
  """
  @spec normalise_title(term()) :: String.t() | nil
  def normalise_title(value), do: Institution.normalise(value)

  @doc """
  `answers` with the booker's title kept in it, for a booking on a type the
  fields apply to; `answers` unchanged otherwise, or when there is no title.
  """
  @spec put_title(map() | nil, map() | nil, term()) :: map()
  def put_title(answers, meeting_type, title) do
    answers = answers || %{}

    case {applies?(meeting_type), normalise_title(title)} do
      {true, title} when is_binary(title) -> Map.put(answers, @answer_key, title)
      _none -> answers
    end
  end

  @doc "The title a booking request was made with, or `nil`."
  @spec title(map() | nil) :: String.t() | nil
  def title(%{} = meeting) do
    case Map.get(meeting, :custom_field_answers) do
      %{} = answers -> normalise_title(Map.get(answers, @answer_key))
      _none -> nil
    end
  end

  def title(_meeting), do: nil

  @doc "Whether `meeting` was booked as a request with a title."
  @spec request?(map() | nil) :: boolean()
  def request?(meeting), do: is_binary(title(meeting))

  @doc """
  The organiser's title of a request: "<title> x <institution>", or
  "<title> x <name>" without an institution, or the title alone when neither
  is there. `nil` without a title.
  """
  @spec organiser_title(term(), term(), term()) :: String.t() | nil
  def organiser_title(title, institution, name) do
    case {normalise_title(title),
          Institution.normalise(institution) || Institution.normalise(name)} do
      {nil, _who} -> nil
      {title, nil} -> title
      {title, who} -> "#{title} x #{who}"
    end
  end

  @doc """
  Whether `title` is the organiser's title `organiser_title/3` built for
  `meeting`, from the title, institution and name the meeting holds.
  """
  @spec organiser_title?(map()) :: boolean()
  def organiser_title?(%{title: stored} = meeting) when is_binary(stored) do
    case organiser_title(
           title(meeting),
           Map.get(meeting, :attendee_company),
           Map.get(meeting, :attendee_name)
         ) do
      nil -> false
      built -> built == stored
    end
  end

  def organiser_title?(_meeting), do: false

  defp group?(%{max_participants: max}) when is_integer(max), do: max > 1
  defp group?(_meeting_type), do: false
end
