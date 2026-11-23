defmodule Tymeslot.Bookings.Institution do
  @moduledoc """
  The booker's institution or company (Revision Dynamics,
  `rd-institution-title.patch`).

  The booking form asks for it (`TymeslotWeb.Themes.Shared.Components.BookingForm`),
  the submission validates it (`Tymeslot.Security.FieldValidators.InstitutionValidator`)
  and the booking keeps it in the meeting's `attendee_company` column, which
  the dashboard and the organiser's emails already show. It also names the
  organiser's calendar event and Teams meeting,
  "<meeting type> x <institution>" (`Tymeslot.Bookings.BookingTitle`).

  The field is on unless `config :tymeslot, :booking_institution_field` is
  `false`. The test suite turns it off (`config/test.exs`), as the suite's
  bookings give a name, an email and a message only; the tests of the field
  turn it on.
  """

  @max_length 120

  # Control characters (line breaks and tabs among them) and the line and
  # paragraph separators become a space: the value is one line in an email
  # header, a calendar title and an iCalendar property. Invisible format
  # characters (zero-width spaces, bidirectional overrides) are dropped.
  @to_space ~r/[\p{Cc}\p{Zl}\p{Zp}]+/u
  @invisible ~r/\p{Cf}+/u
  @whitespace ~r/\s+/u

  @doc "Whether the booking form asks for the institution."
  @spec field_enabled?() :: boolean()
  def field_enabled?,
    do: Application.get_env(:tymeslot, :booking_institution_field, true) != false

  @doc "The most characters an institution may have, after `normalise/1`."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc """
  The institution as it is stored and shown: control characters and line
  breaks turned into spaces, invisible format characters dropped, runs of
  whitespace collapsed to one space, and the ends trimmed. `nil` for a value
  that is blank afterwards or not text.

  It does not shorten: a value longer than `max_length/0` is refused by the
  form's validation rather than cut.

      iex> Tymeslot.Bookings.Institution.normalise("  Montessori-Schule\\n Idstein ")
      "Montessori-Schule Idstein"

      iex> Tymeslot.Bookings.Institution.normalise(" \\t ")
      nil
  """
  @spec normalise(term()) :: String.t() | nil
  def normalise(value) when is_binary(value) do
    if String.valid?(value) do
      value
      |> String.replace(@to_space, " ")
      |> String.replace(@invisible, "")
      |> String.replace(@whitespace, " ")
      |> String.trim()
      |> blank_to_nil()
    end
  end

  def normalise(_value), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
