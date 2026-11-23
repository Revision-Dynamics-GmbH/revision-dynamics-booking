defmodule Tymeslot.Security.FieldValidators.RequestDescriptionValidator do
  @moduledoc """
  The description of a booking request (`Tymeslot.Bookings.RequestFields`),
  the form's message field under another label: required, and at most
  `Tymeslot.Bookings.RequestFields.description_max_length/0` characters with
  its ends trimmed. Line breaks are kept; it is a text of its own, not a line.
  A value that is not text counts as none.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Bookings.RequestFields

  @doc """
  Validates a request description.

      iex> validate("Wir möchten die Einführung im Kollegium besprechen.")
      :ok

      iex> validate(" \\n ")
      {:error, "Please describe briefly what it is about."}
  """
  @spec validate(any(), keyword()) :: :ok | {:error, String.t()}
  def validate(value, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, RequestFields.description_max_length())

    case value do
      text when is_binary(text) ->
        trimmed = String.trim(text)

        cond do
          trimmed == "" ->
            {:error, dgettext("errors_input", "Please describe briefly what it is about.")}

          String.length(trimmed) > max_length ->
            {:error,
             dgettext(
               "errors_input",
               "The description is too long (maximum %{max_length} characters).",
               max_length: max_length
             )}

          true ->
            :ok
        end

      _not_text ->
        {:error, dgettext("errors_input", "Please describe briefly what it is about.")}
    end
  end
end
