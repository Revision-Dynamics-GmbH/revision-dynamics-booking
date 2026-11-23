defmodule Tymeslot.Bookings.RequestFieldsTest do
  @moduledoc """
  Title and description of a booking request (Revision Dynamics,
  rd-request-fields.patch): which types ask for them, how they are checked,
  kept and named. The fields are off for the suite (`config/test.exs`), so
  these tests turn them on, which is global application env: not async.
  """

  use ExUnit.Case, async: false

  import Tymeslot.ConfigTestHelpers

  alias Tymeslot.Bookings.BookingTitle
  alias Tymeslot.Bookings.RequestFields
  alias Tymeslot.Security.FieldValidators.RequestDescriptionValidator
  alias Tymeslot.Security.FieldValidators.RequestTitleValidator
  alias Tymeslot.Security.InputProcessor
  alias TymeslotWeb.Live.Scheduling.BookingConfig

  @request_type %{requires_approval: true, max_participants: 1}
  @direct_type %{requires_approval: false, max_participants: 1}
  @group_request %{requires_approval: true, max_participants: 8}

  setup do
    with_config(:tymeslot, booking_request_fields: true, booking_institution_field: true)
  end

  describe "which types ask" do
    test "a type that holds its bookings for approval, one person at a time" do
      assert RequestFields.applies?(@request_type)
      refute RequestFields.applies?(@direct_type)
      refute RequestFields.applies?(@group_request)
      refute RequestFields.applies?(nil)
    end

    test "nothing asks while the fields are off" do
      with_config(:tymeslot, booking_request_fields: false)
      refute RequestFields.applies?(@request_type)
    end
  end

  describe "the form's field spec" do
    @params %{"name" => "Max Mustermann", "email" => "max@example.com"}

    test "a request type requires a title and a description, the institution is optional" do
      spec = BookingConfig.booking_field_spec(@request_type)

      assert {:error, errors} =
               InputProcessor.validate_form(Map.put(@params, "message", ""), spec)

      assert errors.title == "Please enter a title."
      assert errors.message == "Please describe briefly what it is about."
      refute Map.has_key?(errors, :company)

      assert {:ok, %{"title" => "Abstimmung Pilotphase", "company" => ""}} =
               InputProcessor.validate_form(
                 Map.merge(@params, %{
                   "title" => "Abstimmung Pilotphase",
                   "message" => "Wir möchten die Einführung besprechen.",
                   "company" => ""
                 }),
                 spec
               )
    end

    test "a type without requests keeps its fields, the institution required" do
      spec = BookingConfig.booking_field_spec(@direct_type)
      refute Enum.any?(spec, &(elem(&1, 0) == "title"))

      assert {:error, %{company: "Institution or company is required"}} =
               InputProcessor.validate_form(Map.put(@params, "message", ""), spec)

      assert BookingConfig.booking_field_spec() == spec
    end

    test "every field a form may carry is kept when it closes and opens again" do
      assert BookingConfig.field_names() == ~w(name email message company title)
    end
  end

  describe "validators" do
    test "the title is one line of at most 120 characters" do
      assert :ok = RequestTitleValidator.validate("Abstimmung Pilotphase")
      assert :ok = RequestTitleValidator.validate(" Zwei\nZeilen ")
      assert {:error, "Please enter a title."} = RequestTitleValidator.validate(" \t ")
      assert {:error, "Please enter a title."} = RequestTitleValidator.validate(nil)
      assert {:error, "Please enter a title."} = RequestTitleValidator.validate(["a"])
      assert :ok = RequestTitleValidator.validate(String.duplicate("a", 120))

      assert {:error, "The title is too long (maximum 120 characters)."} =
               RequestTitleValidator.validate(String.duplicate("a", 121))
    end

    test "the description keeps its lines, at most 2000 characters" do
      assert :ok = RequestDescriptionValidator.validate("Erstens.\nZweitens.")

      assert {:error, "Please describe briefly what it is about."} =
               RequestDescriptionValidator.validate(" \n ")

      assert {:error, "Please describe briefly what it is about."} =
               RequestDescriptionValidator.validate(nil)

      assert :ok = RequestDescriptionValidator.validate(String.duplicate("a", 2000))

      assert {:error, "The description is too long (maximum 2000 characters)."} =
               RequestDescriptionValidator.validate(String.duplicate("a", 2001))
    end
  end

  describe "keeping and naming" do
    test "the title is kept among the answers, under its reserved key" do
      answers =
        RequestFields.put_title(%{"q1" => "yes"}, @request_type, "  Abstimmung\n Pilotphase ")

      assert answers == %{"q1" => "yes", "rd_request_title" => "Abstimmung Pilotphase"}

      assert RequestFields.put_title(%{}, @direct_type, "Abstimmung") == %{}
      assert RequestFields.put_title(nil, @request_type, "  ") == %{}

      meeting = %{custom_field_answers: answers}
      assert RequestFields.title(meeting) == "Abstimmung Pilotphase"
      assert RequestFields.request?(meeting)
      refute RequestFields.request?(%{custom_field_answers: %{}})
      refute RequestFields.request?(%{custom_field_answers: nil})
      refute RequestFields.request?(nil)
    end

    test "the organiser's title names the institution, else the person" do
      assert RequestFields.organiser_title("Abstimmung", "Montessori-Schule Idstein", "Max") ==
               "Abstimmung x Montessori-Schule Idstein"

      assert RequestFields.organiser_title("Abstimmung", " ", "Max Mustermann") ==
               "Abstimmung x Max Mustermann"

      assert RequestFields.organiser_title("Abstimmung", nil, nil) == "Abstimmung"
      assert RequestFields.organiser_title(" ", "Schule", "Max") == nil
    end

    test "the booker reads the meeting as '<type> with <name>', not the organiser's title" do
      meeting = %{
        title: "Abstimmung x Beispiel GmbH",
        meeting_type: "Individueller Termin",
        attendee_name: "Max Mustermann",
        attendee_company: "Beispiel GmbH",
        custom_field_answers: %{"rd_request_title" => "Abstimmung"}
      }

      assert RequestFields.organiser_title?(meeting)
      assert BookingTitle.localise(meeting, "en") == "Individueller Termin with Max Mustermann"

      renamed = %{meeting | title: "Von Tim umbenannt"}
      refute RequestFields.organiser_title?(renamed)
      assert BookingTitle.localise(renamed, "en") == "Von Tim umbenannt"
    end
  end
end
