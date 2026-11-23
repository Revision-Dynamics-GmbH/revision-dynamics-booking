defmodule TymeslotWeb.Live.Scheduling.InstitutionFieldTest do
  @moduledoc """
  The booking form's institution or company (Revision Dynamics,
  rd-institution-title.patch) on every shipped theme: asked for, required,
  validated on the server, and naming the organiser's calendar entry
  "<meeting type> x <institution>"; shown to the organiser on their dashboard.

  The suite runs with the field off (`config/test.exs`), so these tests turn
  it on, which is global application env: not async.
  """

  use TymeslotWeb.LiveCase, async: false
  @moduletag :bookings

  import Mox
  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.BookingTestHelpers, only: [seed_booking_account: 3]
  import Tymeslot.ConfigTestHelpers

  alias Ecto.Changeset
  alias Plug.Test
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo
  alias Tymeslot.Security.FieldValidators.InstitutionValidator
  alias Tymeslot.Security.InputProcessor
  alias Tymeslot.TestMocks
  alias TymeslotWeb.BookingDriver
  alias TymeslotWeb.Live.Scheduling.BookingConfig

  @timezone "Europe/Berlin"
  @field "form[data-fact='attendee'] input[name='booking[company]']"

  # The four shipped themes, by id and slug (`TymeslotWeb.ThemeTestMatrix`).
  @themes [{"1", "quill"}, {"2", "rhythm"}, {"3", "paper"}, {"4", "folio"}]

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)

    TestMocks.setup_email_mocks()
    TestMocks.setup_subscription_mocks()

    Tymeslot.CalendarMock
    |> stub(:get_events_for_range_fresh, fn _user_id, _start_date, _end_date -> {:ok, []} end)
    |> stub(:get_booking_integration_info, fn _user_id -> {:error, :no_integration} end)

    :ok
  end

  describe "with the field on" do
    setup do
      with_config(:tymeslot, booking_institution_field: true)
    end

    for {theme_id, slug} <- @themes do
      @tag :capture_log
      test "#{slug}: asks for it and titles the organiser's entry with it", %{conn: conn} do
        %{user: user, profile: profile} =
          seed_booking_account(unquote(theme_id), "inst-#{unquote(slug)}", @timezone)

        view = open_booking_form(conn, profile)

        assert has_element?(
                 view,
                 "#{@field}[required][maxlength='120'][autocomplete='organization']"
               )

        assert render(view) =~ "Institution or company"

        BookingDriver.submit(view, %{
          name: "Max Mustermann",
          email: "max-#{unquote(slug)}@example.com",
          company: "  Montessori-Schule\n Idstein ",
          message: ""
        })

        meeting = Repo.get_by!(MeetingSchema, organizer_user_id: user.id)

        assert meeting.title == "Quick Chat x Montessori-Schule Idstein"
        assert meeting.summary == meeting.title
        assert meeting.attendee_company == "Montessori-Schule Idstein"
      end
    end

    @tag :capture_log
    test "a booking without it is refused, and the field says why", %{conn: conn} do
      %{user: user, profile: profile} = seed_booking_account("3", "inst-missing", @timezone)
      view = open_booking_form(conn, profile)

      html =
        BookingDriver.submit(view, %{
          name: "Max Mustermann",
          email: "max-missing@example.com",
          company: " \n ",
          message: ""
        })

      assert html =~ "Institution or company is required"
      refute Repo.get_by(MeetingSchema, organizer_user_id: user.id)
    end

    @tag :capture_log
    test "a value longer than 120 characters is refused", %{conn: conn} do
      %{user: user, profile: profile} = seed_booking_account("3", "inst-long", @timezone)
      view = open_booking_form(conn, profile)

      html =
        BookingDriver.submit(view, %{
          name: "Max Mustermann",
          email: "max-long@example.com",
          company: String.duplicate("a", 121),
          message: ""
        })

      assert html =~ "Institution or company is too long (maximum 120 characters)"
      refute Repo.get_by(MeetingSchema, organizer_user_id: user.id)
    end

    @tag :capture_log
    test "the organiser's dashboard shows who booked from which institution", %{conn: conn} do
      %{user: user, profile: profile} = seed_booking_account("3", "inst-dashboard", @timezone)
      view = open_booking_form(conn, profile)

      BookingDriver.submit(view, %{
        name: "Max Mustermann",
        email: "max-dashboard@example.com",
        company: "Beispiel GmbH",
        message: ""
      })

      assert Repo.get_by!(MeetingSchema, organizer_user_id: user.id).attendee_company ==
               "Beispiel GmbH"

      user =
        user
        |> Changeset.change(onboarding_completed_at: DateTime.utc_now(:second))
        |> Repo.update!()

      host_conn =
        build_conn()
        |> Test.init_test_session(%{})
        |> fetch_session()
        |> log_in_user(user)

      {:ok, dashboard, _html} = live(host_conn, ~p"/dashboard/meetings")

      assert render(dashboard) =~ "Max Mustermann"
      assert render(dashboard) =~ "Beispiel GmbH"
    end

    test "the form's field spec asks for it" do
      params = %{"name" => "Max Mustermann", "email" => "max@example.com", "message" => ""}
      spec = BookingConfig.booking_field_spec()

      assert {"company", InstitutionValidator} in spec

      assert {:error, %{company: "Institution or company is required"}} =
               InputProcessor.validate_form(params, spec)

      assert {:ok, %{"company" => "Beispiel GmbH"}} =
               InputProcessor.validate_form(Map.put(params, "company", " Beispiel GmbH "), spec)

      # Markup is stripped, as from the name.
      assert {:ok, %{"company" => company}} =
               InputProcessor.validate_form(
                 Map.put(params, "company", "<b>Beispiel</b> GmbH"),
                 spec
               )

      assert company == "Beispiel GmbH"
    end
  end

  describe "with the field off" do
    setup do
      with_config(:tymeslot, booking_institution_field: false)
    end

    @tag :capture_log
    test "the form does not ask for it, and the title names the booker", %{conn: conn} do
      %{user: user, profile: profile} = seed_booking_account("3", "inst-off", @timezone)
      view = open_booking_form(conn, profile)

      refute has_element?(view, @field)
      refute Enum.any?(BookingConfig.booking_field_spec(), &(elem(&1, 0) == "company"))

      BookingDriver.submit(view, %{
        name: "Max Mustermann",
        email: "max-off@example.com",
        message: ""
      })

      meeting = Repo.get_by!(MeetingSchema, organizer_user_id: user.id)

      assert meeting.title == "Quick Chat with Max Mustermann"
      assert meeting.attendee_company == nil
    end
  end

  defp open_booking_form(conn, profile) do
    {:ok, view, _html} = live(conn, ~p"/#{profile.username}?timezone=#{@timezone}")
    BookingDriver.book(view, until: :attendee)
    view
  end
end
