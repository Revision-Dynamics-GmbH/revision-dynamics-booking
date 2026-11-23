defmodule Tymeslot.Security.FieldValidators.RequestTitleValidator do
  @moduledoc """
  The title of a booking request (`Tymeslot.Bookings.RequestFields`):
  required, and at most `Tymeslot.Bookings.RequestFields.title_max_length/0`
  characters once normalised to one line, the form in which it is stored.
  Line breaks and control characters are normalised away rather than refused.
  A value that is not text counts as none.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Bookings.RequestFields

  @doc """
  Validates a request title.

      iex> validate("Abstimmung Pilotphase")
      :ok

      iex> validate("  ")
      {:error, "Please enter a title."}
  """
  @spec validate(any(), keyword()) :: :ok | {:error, String.t()}
  def validate(value, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, RequestFields.title_max_length())

    case RequestFields.normalise_title(value) do
      nil ->
        {:error, dgettext("errors_input", "Please enter a title.")}

      title ->
        if String.length(title) > max_length,
          do:
            {:error,
             dgettext("errors_input", "The title is too long (maximum %{max_length} characters).",
               max_length: max_length
             )},
          else: :ok
    end
  end
end
