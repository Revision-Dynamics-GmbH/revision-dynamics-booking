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
  """

  alias Tymeslot.Bookings.Institution
  alias Tymeslot.Security.FieldValidators.InstitutionValidator

  @booking_field_spec [
    {"name", :name},
    {"email", :email},
    {"message", :message, [required: false, min_length: 0]}
  ]

  @institution_field_spec {"company", InstitutionValidator}

  @typedoc "A single booking field specification entry."
  @type field_spec_entry :: {String.t(), atom()} | {String.t(), atom(), keyword()}

  @doc """
  Returns the booking field spec for use with `InputProcessor.validate_form/2`.
  """
  @spec booking_field_spec() :: [field_spec_entry()]
  def booking_field_spec do
    if Institution.field_enabled?(),
      do: @booking_field_spec ++ [@institution_field_spec],
      else: @booking_field_spec
  end
end
