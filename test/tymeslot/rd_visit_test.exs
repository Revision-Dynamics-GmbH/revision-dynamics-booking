defmodule Tymeslot.RdVisitTest do
  @moduledoc """
  On-site visits booked from the website (Revision Dynamics,
  `rd-visit-service.patch`): the request's limits, the internal listener's
  secret, the busy times with their places, the booking with its drive
  there and back, the guest's missing reschedule link and the clean-up when
  the visit is cancelled.
  """

  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  import Mox
  import Plug.Conn
  import Plug.Test
  import Tymeslot.Factory

  alias Tymeslot.Bookings.MeetingLinks
  alias Tymeslot.Bookings.Policy
  alias Tymeslot.Integrations.Calendar.CreatedEvent
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Notifications.Events
  alias Tymeslot.RdVisit
  alias Tymeslot.RdVisit.Request
  alias TymeslotWeb.RdVisitInternal

  @secret String.duplicate("s", 40)

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    System.put_env("RD_VISIT_SECRET", @secret)
    System.put_env("RD_VISIT_USERNAME", "visit-host")

    on_exit(fn ->
      System.delete_env("RD_VISIT_SECRET")
      System.delete_env("RD_VISIT_USERNAME")
    end)

    user = insert(:user, email: "host@example.com")
    insert(:profile, user: user, username: "visit-host", timezone: "Europe/Berlin")
    integration = insert(:calendar_integration, user: user, provider: "caldav")

    stub(Tymeslot.CalendarMock, :get_events_for_range_fresh, fn _user, _from, _to -> {:ok, []} end)

    stub(Tymeslot.CalendarMock, :get_booking_integration_info, fn _context ->
      {:ok, %{integration_id: integration.id, calendar_path: "visits"}}
    end)

    %{user: user, integration: integration}
  end

  defp at(days, hour, minute \\ 0) do
    Date.utc_today()
    |> Date.add(days)
    |> DateTime.new!(Time.new!(hour, minute, 0), "Europe/Berlin")
  end

  defp params(start, overrides \\ %{}) do
    Map.merge(
      %{
        "start" => DateTime.to_iso8601(start),
        "minutes" => 90,
        "address" => "Rheinstraße 1 64283 Darmstadt",
        "name" => "Erika Mustermann",
        "email" => "erika@example.org",
        "institution" => "Musterschule Darmstadt",
        "locale" => "de",
        "product" => "humanos",
        "travel" => [
          %{
            "start" => DateTime.to_iso8601(DateTime.add(start, -47 * 60)),
            "end" => DateTime.to_iso8601(start),
            "title" => "Anfahrt · Darmstadt",
            "description" => "Abfahrt 09:43 in Schwalbach, etwa 32 Minuten."
          },
          %{
            "start" => DateTime.to_iso8601(DateTime.add(start, 90 * 60)),
            "end" => DateTime.to_iso8601(DateTime.add(start, 122 * 60)),
            "title" => "Rückfahrt · Darmstadt",
            "description" => "Etwa 32 Minuten bis Schwalbach."
          }
        ]
      },
      overrides
    )
  end

  defp eventually(check, tries \\ 40) do
    cond do
      check.() -> true
      tries == 0 -> false
      true -> Process.sleep(25) && eventually(check, tries - 1)
    end
  end

  defp internal(method, path, body \\ nil, secret \\ @secret) do
    conn = conn(method, path, body && Jason.encode!(body))

    conn =
      if body, do: put_req_header(conn, "content-type", "application/json"), else: conn

    conn =
      if secret, do: put_req_header(conn, "authorization", "Bearer " <> secret), else: conn

    RdVisitInternal.call(conn, RdVisitInternal.init([]))
  end

  describe "the request" do
    test "takes the website's booking and refuses anything out of shape" do
      start = at(3, 10, 30)
      assert {:ok, request} = Request.parse(params(start))
      assert DateTime.compare(request.end, DateTime.add(start, 90 * 60)) == :eq
      assert length(request.travel) == 2

      for change <- [
            %{"start" => DateTime.to_iso8601(at(-1, 10))},
            %{"minutes" => 45},
            %{"minutes" => 120},
            %{"email" => "not-an-address"},
            %{"name" => String.duplicate("n", 121)},
            %{"address" => "ab"},
            %{"institution" => " "},
            %{"institution" => String.duplicate("i", 121)},
            %{"locale" => "fr"},
            %{"product" => "other"},
            %{"travel" => List.duplicate(hd(params(start)["travel"]), 5)},
            %{
              "travel" => [
                %{
                  "start" => DateTime.to_iso8601(at(1, 9)),
                  "end" => DateTime.to_iso8601(at(1, 10)),
                  "title" => "Weit weg",
                  "description" => ""
                }
              ]
            }
          ] do
        assert {:error, :invalid} = Request.parse(params(start, change)), inspect(change)
      end
    end
  end

  describe "the internal listener" do
    test "answers only with the shared secret" do
      assert internal(:get, "/visit/health", nil, nil).status == 401
      assert internal(:get, "/visit/health", nil, String.duplicate("x", 40)).status == 401
      assert internal(:get, "/visit/health").status == 200
    end

    test "does not start without a secret of 32 characters" do
      System.put_env("RD_VISIT_SECRET", "short")
      assert RdVisitInternal.children() == []
      System.put_env("RD_VISIT_SECRET", @secret)
      assert [%{id: :rd_visit_internal}] = RdVisitInternal.children()
    end

    test "reads busy times with their places and refuses a long window", %{user: user} do
      start = at(2, 11)

      stub(Tymeslot.CalendarMock, :get_events_for_range_fresh, fn _user, _from, _to ->
        {:ok,
         [
           %{
             start_time: start,
             end_time: DateTime.add(start, 3600),
             location: "Schulweg 3 65439 Flörsheim",
             transparency: "opaque"
           },
           %{
             start_time: DateTime.add(start, 7200),
             end_time: DateTime.add(start, 9000),
             location: "Microsoft Teams-Besprechung",
             transparency: "opaque"
           },
           %{
             start_time: DateTime.add(start, 10_800),
             end_time: DateTime.add(start, 12_600),
             location: "Frei",
             transparency: "transparent"
           }
         ]}
      end)

      insert(:meeting,
        organizer_user_id: user.id,
        start_time: DateTime.add(start, 14_400),
        end_time: DateTime.add(start, 18_000),
        location: "Marktplatz 1 64283 Darmstadt",
        status: :confirmed
      )

      day = Date.add(Date.utc_today(), 2)

      conn =
        internal(:post, "/visit/busy", %{
          "from" => Date.to_iso8601(day),
          "to" => Date.to_iso8601(Date.add(day, 1))
        })

      assert conn.status == 200
      events = Jason.decode!(conn.resp_body)["events"]

      assert Enum.map(events, & &1["location"]) == [
               "Schulweg 3 65439 Flörsheim",
               nil,
               "Marktplatz 1 64283 Darmstadt"
             ]

      assert internal(:post, "/visit/busy", %{
               "from" => Date.to_iso8601(day),
               "to" => Date.to_iso8601(Date.add(day, 30))
             }).status == 422
    end
  end

  describe "booking a visit" do
    test "books at the address with the drive there and back, once", %{integration: integration} do
      start = at(4, 10, 30)
      test_pid = self()

      expect(Tymeslot.CalendarMock, :create_event, 2, fn data, {integration_id, _user} ->
        assert integration_id == integration.id
        assert data.calendar_id == "visits"
        assert data.show_as == "busy"
        assert data.attendees == []
        assert is_binary(data.uid)
        send(test_pid, {:travel, data.summary})
        {:ok, %CreatedEvent{uid: "travel-#{data.summary}", provider_event_id: nil}}
      end)

      conn = internal(:post, "/visit/book", params(start))
      assert conn.status == 201
      assert_received {:travel, "Anfahrt · Darmstadt"}
      assert_received {:travel, "Rückfahrt · Darmstadt"}

      [meeting] = Repo.all(MeetingSchema)
      assert meeting.location == "Rheinstraße 1 64283 Darmstadt"
      assert meeting.meeting_type == "HumanOS vor Ort"
      assert meeting.title == "HumanOS vor Ort x Musterschule Darmstadt"
      assert meeting.attendee_company == "Musterschule Darmstadt"
      assert meeting.calendar_integration_id == integration.id
      assert meeting.video_integration_id == nil
      assert DateTime.compare(meeting.start_time, start) == :eq
      assert meeting.duration == 90
      assert RdVisit.visit?(meeting)
      assert length(meeting.tracking_params["rd_visit"]["travel"]) == 2

      # The guest cancels, never moves: Tymeslot's page knows nothing of the drive.
      assert Policy.can_booker_move_meeting?(meeting) == {:error, :managed_by_host}
      links = MeetingLinks.for_meeting(meeting)
      assert links.reschedule_url == nil
      assert is_binary(links.cancel_url)

      # The same time again overlaps the visit.
      assert internal(:post, "/visit/book", params(start)).status == 409
      assert Repo.aggregate(MeetingSchema, :count) == 1
    end

    test "refuses a time the calendar has filled in the meantime" do
      start = at(5, 13)

      stub(Tymeslot.CalendarMock, :get_events_for_range_fresh, fn _user, _from, _to ->
        {:ok,
         [
           %{
             start_time: DateTime.add(start, -30 * 60),
             end_time: DateTime.add(start, -15 * 60),
             location: nil,
             transparency: "opaque"
           }
         ]}
      end)

      # The drive there starts 47 minutes before the visit: the entry is in its way.
      assert internal(:post, "/visit/book", params(start)).status == 409
      assert Repo.all(MeetingSchema) == []
    end

    test "a cancelled visit takes its drive out of the calendar" do
      start = at(6, 9, 45)
      test_pid = self()

      stub(Tymeslot.CalendarMock, :create_event, fn data, _context ->
        {:ok, %CreatedEvent{uid: "travel-#{data.summary}", provider_event_id: nil}}
      end)

      assert internal(:post, "/visit/book", params(start)).status == 201
      [meeting] = Repo.all(MeetingSchema)

      expect(Tymeslot.CalendarMock, :delete_event, 2, fn uid, _context, _opts ->
        send(test_pid, {:deleted, uid})
        :ok
      end)

      Events.meeting_cancelled(%{meeting | status: :cancelled}, emails: false)

      assert_receive {:deleted, "travel-Anfahrt · Darmstadt"}, 2_000
      assert_receive {:deleted, "travel-Rückfahrt · Darmstadt"}, 2_000

      assert eventually(fn ->
               Repo.reload(meeting).tracking_params["rd_visit"]["travel"] == []
             end)
    end

    test "an OrganisationOS visit is 90 minutes like every visit" do
      stub(Tymeslot.CalendarMock, :create_event, fn data, _context ->
        {:ok, %CreatedEvent{uid: "travel-#{data.summary}", provider_event_id: nil}}
      end)

      start = at(8, 10)

      assert internal(
               :post,
               "/visit/book",
               params(start, %{"product" => "organisationos", "locale" => "en"})
             ).status == 201

      [meeting] = Repo.all(MeetingSchema)
      assert meeting.duration == 90
      assert DateTime.compare(meeting.end_time, DateTime.add(start, 90 * 60)) == :eq
      assert meeting.meeting_type == "OrganisationOS on site"
      assert meeting.title == "OrganisationOS on site x Musterschule Darmstadt"
    end

    test "a calendar that fails on the drive keeps the booking" do
      stub(Tymeslot.CalendarMock, :create_event, fn _data, _context -> raise "calendar down" end)
      assert internal(:post, "/visit/book", params(at(7, 11))).status == 201
      [meeting] = Repo.all(MeetingSchema)
      assert meeting.tracking_params["rd_visit"]["travel"] == []
    end

    test "leaves every other meeting alone" do
      refute RdVisit.visit?(%{tracking_params: %{}})
      refute RdVisit.visit?(%{tracking_params: nil})
      assert RdVisit.release_travel(%{id: 1, tracking_params: %{}}) == :ok
    end
  end
end
