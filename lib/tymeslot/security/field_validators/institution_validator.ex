defmodule Tymeslot.Security.FieldValidators.InstitutionValidator do
  @moduledoc """
  The booking form's institution or company (`Tymeslot.Bookings.Institution`):
  required, and at most `Tymeslot.Bookings.Institution.max_length/0`
  characters once normalised, the form in which it is stored. Line breaks and
  control characters are not refused but normalised away, so a pasted value
  that spans two lines books as one line. A value that is not text (a list or
  a map from a hand-made request) counts as none.

  Options:

    * `:required` (default `true`): when `false`, a blank value is valid.
    * `:max_length` (default `Tymeslot.Bookings.Institution.max_length/0`).
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Bookings.Institution

  @doc """
  Validates an institution or company.

      iex> validate("Montessori-Schule Idstein")
      :ok

      iex> validate("   ")
      {:error, "Institution or company is required"}
  """
  @spec validate(any(), keyword()) :: :ok | {:error, String.t()}
  def validate(value, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, Institution.max_length())

    case Institution.normalise(value) do
      nil ->
        if Keyword.get(opts, :required, true),
          do: {:error, dgettext("errors_input", "Institution or company is required")},
          else: :ok

      institution ->
        if String.length(institution) > max_length,
          do:
            {:error,
             dgettext(
               "errors_input",
               "Institution or company is too long (maximum %{max_length} characters)",
               max_length: max_length
             )},
          else: :ok
    end
  end
end
