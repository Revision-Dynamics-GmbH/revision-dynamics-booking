defmodule Tymeslot.Bookings.BookingTitle do
  @moduledoc """
  The title a booking is given, "<meeting type> with <name>", and the same
  title in another reader's language.

  A booking's `title` is stored once, in the organiser's language, because it
  becomes the organiser's calendar event and dashboard entry. The booker and
  their guests read it too, in their emails and the `.ics` attached to them,
  so `localise/1` renders it again in the current Gettext locale for them.

  Only a title this template built is rendered again. A title that does not
  match the template in any language (one renamed in the calendar grid, a
  demo booking's, or one whose attendee name has since been edited) is the
  stored text, and is returned as it is.

  A booker who named their institution or company
  (`Tymeslot.Bookings.Institution`, Revision Dynamics) gives the organiser's
  title instead as "<meeting type> x <institution>" (`organiser_title/3`), so
  the organiser's calendar shows who the meeting is with at a glance. That
  title is the organiser's alone: the booker and their guests read it as
  "<meeting type> with <name>" in their language, as they would without one,
  so nothing they are sent changes.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Bookings.Institution

  @doc "The booking title, rendered in the current Gettext locale."
  @spec render(String.t() | nil, String.t() | nil) :: String.t()
  def render(meeting_type, attendee_name) do
    dgettext("emails", "%{meeting_type} with %{name}",
      meeting_type: meeting_type,
      name: attendee_name
    )
  end

  @doc """
  The title a booking is stored with, which names the organiser's calendar
  event, Teams meeting and dashboard entry: "<meeting type> x <institution>"
  for a booker who named their institution (normalised as
  `Tymeslot.Bookings.Institution.normalise/1` stores it), otherwise
  `render/2` in the current Gettext locale. Never an "x" with nothing after
  it: a blank institution, or a booking without a meeting type name, gives
  `render/2`.
  """
  @spec organiser_title(String.t() | nil, String.t() | nil, term()) :: String.t()
  def organiser_title(meeting_type, attendee_name, institution) do
    case {named(meeting_type), Institution.normalise(institution)} do
      {type, institution} when is_binary(type) and is_binary(institution) ->
        institution_title(type, institution)

      _no_institution ->
        render(meeting_type, attendee_name)
    end
  end

  @doc """
  The meeting's title in the current Gettext locale when this template built
  it, otherwise its stored `title` unchanged. A title naming the booker's
  institution (`organiser_title/3`) reads as `render/2`, the title the
  booker's side has always shown.
  """
  @spec localise(map()) :: String.t() | nil
  def localise(
        %{title: title, meeting_type: meeting_type, attendee_name: attendee_name} = meeting
      )
      when is_binary(title) and is_binary(meeting_type) and is_binary(attendee_name) do
    if built_from_template?(title, meeting_type, attendee_name) or
         institution_title?(meeting),
       do: render(meeting_type, attendee_name),
       else: title
  end

  def localise(meeting), do: Map.get(meeting, :title)

  @doc "`localise/1` in `locale`."
  @spec localise(map(), String.t()) :: String.t() | nil
  def localise(meeting, locale),
    do: Gettext.with_locale(TymeslotWeb.Gettext, locale, fn -> localise(meeting) end)

  @doc """
  `localise/1` with the meeting type named `display_type`, the name as the
  reader sees it (the attendee's translation of it,
  `Tymeslot.ContentTranslations.AttendeeTexts`). The template is still
  detected from the stored, original name, so a title it did not build is
  returned unchanged.

  A title that is just the stored meeting type name, as a group slot's or a
  planned session's is (`Tymeslot.Bookings.SeatEffects.slot_attrs/2`),
  names the type, so it reads as `display_type` too.
  """
  @spec localise_with_type(map(), String.t() | nil) :: String.t() | nil
  def localise_with_type(%{title: title, meeting_type: title}, display_type)
      when is_binary(title) and is_binary(display_type),
      do: display_type

  def localise_with_type(
        %{title: title, meeting_type: meeting_type, attendee_name: attendee_name} = meeting,
        display_type
      )
      when is_binary(title) and is_binary(meeting_type) and is_binary(attendee_name) and
             is_binary(display_type) do
    if built_from_template?(title, meeting_type, attendee_name) or
         institution_title?(meeting),
       do: render(display_type, attendee_name),
       else: localise(meeting)
  end

  def localise_with_type(meeting, _display_type), do: localise(meeting)

  # Every catalogue is tried, not only the organiser's current language: the
  # title was rendered in whatever language they had when the booking was
  # made, and bookings older than the translated title hold the English one.
  defp built_from_template?(title, meeting_type, attendee_name) do
    TymeslotWeb.Gettext
    |> Gettext.known_locales()
    |> Enum.any?(fn locale ->
      Gettext.with_locale(TymeslotWeb.Gettext, locale, fn ->
        render(meeting_type, attendee_name)
      end) == title
    end)
  end

  # The title `organiser_title/3` built from the booking's own institution.
  # A title renamed since, or one naming another institution, is not one.
  defp institution_title?(%{title: title, meeting_type: meeting_type} = meeting) do
    case Institution.normalise(Map.get(meeting, :attendee_company)) do
      nil -> false
      institution -> title == institution_title(meeting_type, institution)
    end
  end

  defp institution_title(meeting_type, institution), do: "#{meeting_type} x #{institution}"

  defp named(meeting_type) when is_binary(meeting_type) do
    case String.trim(meeting_type) do
      "" -> nil
      _name -> meeting_type
    end
  end

  defp named(_meeting_type), do: nil
end
