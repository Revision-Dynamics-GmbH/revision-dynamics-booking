defmodule Tymeslot.Emails.Shared.Meeting.Hero do
  @moduledoc """
  The typographic hero block for meeting emails — 2026 redesign.

  Leads with the date set in display type, the time immediately beneath, and a
  compact metadata grid (type, duration, location) under a hairline. Replaces
  the older 2×2 emoji grid so a meeting reads like a moment, not a form.
  """

  alias Tymeslot.Emails.Shared.{Formatting, Sanitise, Stack, Styles}

  use Gettext, backend: TymeslotWeb.Gettext

  @type meeting_details :: %{
          required(:date) => Date.t() | DateTime.t(),
          required(:start_time) => DateTime.t() | nil,
          required(:duration) => integer() | nil,
          optional(:all_day) => boolean(),
          optional(:last_date) => Date.t() | nil,
          optional(:location) => String.t() | nil,
          optional(:location_type) => atom() | nil,
          optional(:audience) => :host | :guest,
          optional(:meeting_type) => String.t() | nil,
          optional(:event_title) => String.t() | nil,
          optional(:time_format) => String.t() | nil,
          optional(:booking_page_name) => String.t() | nil,
          optional(atom()) => term()
        }

  @doc """
  The hero meeting block, rendered in the recipient's locale.

  An all-day event (`all_day: true`, with `:date` its first day and
  `:last_date` its inclusive last day) has no clock time or duration in
  minutes, so the time line says "All day" and the duration counts days.

  A calendar event, which has a title rather than a meeting type, passes
  `:event_title` instead of `:meeting_type`, and the row is labelled as the
  event.

  A host's copy of a booking made through one of their booking pages
  (`:booking_page_name`) names the page under the meeting type.
  """
  @spec meeting_details_table(meeting_details(), String.t()) :: String.t()
  def meeting_details_table(details, locale) do
    Gettext.with_locale(TymeslotWeb.Gettext, locale, fn ->
      weekday = Formatting.format_weekday(details.date, locale)
      date_line = Formatting.format_date(details.date, locale)
      time_line = Formatting.format_meeting_time(details, locale) || dgettext("emails", "TBD")
      duration = Formatting.format_meeting_duration(details, locale)
      location = Formatting.format_location(details)
      location_note = Formatting.location_note(details)

      rows =
        [
          {dgettext("emails", "Date"), "#{display_weekday(weekday)}, #{date_line}", nil},
          {dgettext("emails", "Time"), time_line, nil},
          title_row(details),
          {dgettext("emails", "Duration"), duration, nil},
          {dgettext("emails", "Location"), location, location_note}
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(fn {_label, value, _note} -> value in [nil, ""] end)

      Stack.spaced("""
      <mj-section padding="8px 0 0 0" background-color="#{Styles.surface()}">
        <mj-column
          background-color="#{Styles.canvas_soft()}"
          border="1px solid #{Styles.hairline()}"
          border-radius="#{Styles.radius(:md)}"
          padding="8px 20px"
          css-class="rd-inset hero-card"
        >
          <mj-table padding="0" css-class="email-hairline-table">
            #{rows |> Enum.with_index() |> Enum.map_join("\n", &row_html/1)}
          </mj-table>
        </mj-column>
      </mj-section>
      """)
    end)
  end

  # Revision Dynamics (rd-mail-brand.patch): the details as calm label/value
  # rows on the inset panel of the shared mail design: label 13px spaced
  # capitals, value 16px, a hairline between rows; on a phone the label
  # stands above its value.
  defp row_html({{label, value, note}, index}) do
    border = if index > 0, do: "border-top: 1px solid #{Styles.hairline()};", else: ""

    """
    <tr>
      <td class="rd-label" width="120" valign="top" style="#{border} padding: 12px 12px 12px 0; width: 120px; font-size: 13px; line-height: 1.45; font-weight: 500; letter-spacing: 0.08em; text-transform: uppercase; color: #{Styles.ink_muted()};">#{Sanitise.sanitize_for_email(label)}</td>
      <td class="rd-value" valign="top" style="#{border} padding: 12px 0; font-size: 16px; line-height: 1.45; font-weight: 500; color: #{Styles.ink()};">#{Sanitise.sanitize_for_email(value)}#{note_html(note)}</td>
    </tr>
    """
  end

  defp note_html(nil), do: ""

  defp note_html(note),
    do:
      ~s(<div style="padding-top: 4px; font-size: 13px; line-height: 1.5; font-weight: 400; color: #{Styles.ink_muted()};">#{Sanitise.sanitize_for_email(note)}</div>)

  defp display_weekday(weekday), do: weekday |> String.downcase() |> String.capitalize()

  defp title_row(%{event_title: title}) when is_binary(title) and title != "",
    do: {dgettext("emails", "Event"), title, nil}

  defp title_row(%{meeting_type: type} = details) when is_binary(type),
    do: {dgettext("emails", "Meeting"), type, Formatting.booked_through(details)}

  defp title_row(_details), do: nil
end
