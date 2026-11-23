defmodule TymeslotWeb.Live.Scheduling.BookingConfig do
  @moduledoc """
  Booking form field configuration shared across all scheduling handlers and themes.

  This is the single source of truth for the booking field spec used by
  `InputProcessor.validate_form/2`. Any new booking fields (e.g. phone, company)
  should be added here — all validation, sanitisation, and form-validity checks
  pick it up automatically.

  The institution or company (`"company"`, Revision Dynamics) is part of the
  spec while `Tymeslot.Bookings.Institution.field_enabled?/0` holds, which is
  read on every call, so the form and its validation always agree.

  A meeting type whose bookings are requests the host approves
  (`Tymeslot.Bookings.RequestFields.applies?/1`, Revision Dynamics,
  rd-request-fields.patch) asks for a title (`"title"`) and makes the message
  its required description; the institution is optional there. Every caller
  passes the meeting type the form books, so the form, its submit button and
  the server's check agree.
  """

  alias Tymeslot.Bookings.Institution
  alias Tymeslot.Bookings.RequestFields
  alias Tymeslot.Security.FieldValidators.InstitutionValidator
  alias Tymeslot.Security.FieldValidators.RequestDescriptionValidator
  alias Tymeslot.Security.FieldValidators.RequestTitleValidator

  @booking_field_spec [
    {"name", :name},
    {"email", :email},
    {"message", :message, [required: false, min_length: 0]}
  ]

  @institution_field_spec {"company", InstitutionValidator}

  @typedoc "A single booking field specification entry."
  @type field_spec_entry :: {String.t(), atom()} | {String.t(), atom(), keyword()}

  @doc """
  Every field a booking form may carry, whatever the meeting type: the ones
  a form keeps when it closes and opens again within one page view.
  """
  @spec field_names() :: [String.t()]
  def field_names, do: ~w(name email message company title)

  @doc """
  Returns the booking field spec for use with `InputProcessor.validate_form/2`,
  for the form of `meeting_type` (nil: a type without requests).
  """
  @spec booking_field_spec(map() | nil) :: [field_spec_entry()]
  def booking_field_spec(meeting_type \\ nil) do
    if RequestFields.applies?(meeting_type),
      do: request_field_spec(),
      else: standard_field_spec()
  end

  defp standard_field_spec do
    if Institution.field_enabled?(),
      do: @booking_field_spec ++ [@institution_field_spec],
      else: @booking_field_spec
  end

  defp request_field_spec do
    [
      {"name", :name},
      {"email", :email},
      {"title", RequestTitleValidator},
      {"message", RequestDescriptionValidator}
    ] ++
      if Institution.field_enabled?(),
        do: [{"company", InstitutionValidator, [required: false]}],
        else: []
  end
end
