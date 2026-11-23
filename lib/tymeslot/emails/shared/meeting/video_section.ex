defmodule Tymeslot.Emails.Shared.Meeting.VideoSection do
  @moduledoc """
  Video-meeting blocks for emails — the ticket-stub join CTA and the matching
  reminder-time pill.

  Both components take an explicit intent so they always match the surrounding
  email's stage band.
  """

  alias Tymeslot.Emails.Shared.{Sanitise, Stack, Styles}
  alias Tymeslot.Emails.Shared.Styles.Tokens

  use Gettext, backend: TymeslotWeb.Gettext

  @doc """
  A video meeting section — ticket-stub feel with a left colour rail and a
  prominent join button. The colour comes from the supplied intent.

  Options: `:title`, `:button_text`. Renders nothing unless `meeting_url` is
  a web address (`Sanitise.safe_web_url?/1`).
  """
  @spec video_meeting_section(Tokens.intent(), String.t() | nil, keyword()) :: String.t()
  def video_meeting_section(intent, meeting_url, opts \\ []) when is_atom(intent) do
    case Sanitise.sanitize_web_url(meeting_url) do
      nil -> ""
      safe_url -> join_section(intent, safe_url, opts)
    end
  end

  # Revision Dynamics (rd-mail-brand.patch): a sentence that says what the
  # button does, then the email's one primary button in the product tone
  # (`Tokens.tone/0`), as the website's `.btn`.
  defp join_section(_intent, safe_url, opts) do
    title = Keyword.get(opts, :title, dgettext("emails", "Join online"))
    button_text = Keyword.get(opts, :button_text, dgettext("emails", "Join online"))

    safe_title = Sanitise.sanitize_for_email(title)
    safe_button_text = Sanitise.sanitize_for_email(button_text)

    product = Tokens.tone()

    Stack.spaced("""
    <mj-section padding="20px 0 4px 0" background-color="#{Styles.surface()}">
      <mj-column>
        <mj-text
          font-size="#{Styles.font_size(:md)}"
          color="#{Tokens.ink_soft()}"
          padding="0 0 14px 0"
          line-height="1.6"
          align="left"
          css-class="mobile-text"
        >
          #{safe_title}
        </mj-text>
        <mj-button
          href="#{safe_url}"
          background-color="#{product.solid}"
          color="#{product.on}"
          font-family="#{Tokens.heading_font_family()}"
          font-weight="600"
          font-size="17px"
          line-height="1.1"
          align="left"
          width="auto"
          inner-padding="#{Styles.button_padding(:medium)}"
          border-radius="#{Styles.radius(:md)}"
          css-class="mobile-button"
        >
          #{safe_button_text}
        </mj-button>
      </mj-column>
    </mj-section>
    """)
  end

  @doc """
  A prominent time alert pill — usually used inside reminder emails. The caller
  supplies the intent explicitly so the pill always matches the email's stage
  band.
  """
  @spec time_alert_badge(Tokens.intent(), String.t()) :: String.t()
  def time_alert_badge(intent, time_text) when is_atom(intent) do
    label = Sanitise.sanitize_for_email(time_text)

    tokens = Styles.intent(intent)

    """
    <mj-section padding="8px 0 16px 0">
      <mj-column>
        <mj-text
          align="left"
          padding="0"
          font-size="0"
        >
          <span style="display: inline-block; padding: 6px 12px; border-radius: #{Styles.radius(:sm)}; background: #{tokens.tint}; color: #{tokens.accent_ink}; font-size: 13px; font-weight: 500; letter-spacing: 0.08em; text-transform: uppercase;">#{label}</span>
        </mj-text>
      </mj-column>
    </mj-section>
    """
  end
end
