defmodule TymeslotWeb.Themes.Shared.Components.ApprovalNotice do
  @moduledoc """
  Tells a booking visitor that this meeting type needs the host's approval.

  Two variants of one fact, sized for where they appear:

    * `pill/1` — a small marker beside a meeting type in the overview list.
      Answers "is there a catch?" at a glance.
    * `block/1` — a fuller sentence on the booking form, the post-payment
      wait screen, and the thank-you screen, where the visitor is deciding
      or has just committed and deserves the whole rule rather than a hint
      of it.

  ## Why this exists at all

  A visitor who picks a time expects to have booked it. On a gated meeting
  type they have not, and the moment they find that out should be *before*
  they submit, not in an email afterwards. Four call sites carry the
  notice, escalating in detail as the commitment grows: the overview
  (`pill/1`, beside the gated type), the booking form (`block/1`,
  `stage: :before`), the post-checkout wait screen for a paid gated type
  (`block/1`, `stage: :after`), and the confirmation screen (`block/1`,
  `stage: :after`). The schedule and questions steps in between carry none
  — the visitor has already seen the pill by then, and repeating the
  notice on every intermediate step would be noise rather than disclosure.

  Neutral class names here; the styling is shared by every theme, in
  `assets/css/scheduling/shared/components/approval-notice.css`, and each theme
  sets its look through the `--approval-*` tokens in its `variables.css`, under
  the token contract (`shared/tokens.css`).

  Callers pass `requires_approval` through `Tymeslot.Meetings.Approval.required?/1`
  rather than reading the field, because SaaS demo organisers supply meeting
  types as plain maps that have no such key.
  """

  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  use TymeslotWeb.Components.CoreComponents, only: [icon: 1]

  alias Tymeslot.Validation.Constraints

  attr :class, :string, default: nil

  @doc "The compact marker, for lists and headers."
  @spec pill(map()) :: Phoenix.LiveView.Rendered.t()
  def pill(assigns) do
    ~H"""
    <span class={["approval-pill", @class]} data-testid="approval-pill">
      <.icon name="hero-hand-raised-micro" class="approval-pill-icon" />
      <span class="approval-pill-text">{dgettext("booking", "Needs approval")}</span>
    </span>
    """
  end

  attr :organizer_name, :string, default: nil
  attr :stage, :atom, default: :before, values: [:before, :after]
  attr :payment_required, :boolean, default: false

  attr :hours, :integer,
    default: nil,
    doc:
      "how long the time is held at most (`Approval.window_hours/1`); the default window when nil"

  attr :class, :string, default: nil

  @doc """
  The fuller notice, for the booking form and the thank-you screen.

  `stage` decides the tense: `:before` warns what will happen, `:after`
  describes what just did. `payment_required` only changes the `:before`
  text, for a meeting type that is both paid and gated: the visitor is
  told they are charged now, ahead of the host's decision, and refunded
  in full if the request is declined or lapses.
  """
  @spec block(map()) :: Phoenix.LiveView.Rendered.t()
  def block(assigns) do
    ~H"""
    <div
      class={["approval-notice", "approval-notice-#{@stage}", @class]}
      data-testid="approval-notice"
    >
      <div class="approval-notice-icon-wrapper">
        <.icon name="hero-hand-raised" class="approval-notice-icon" />
      </div>
      <div class="approval-notice-body">
        <p class="approval-notice-title">{title(assigns)}</p>
        <p class="approval-notice-text">{text(assigns)}</p>
      </div>
    </div>
    """
  end

  defp title(%{stage: :after}), do: dgettext("booking", "Not confirmed yet")
  defp title(_assigns), do: dgettext("booking", "This booking needs approval")

  # Revision Dynamics (rd-request-fields.patch, professor 23.11.2026): a
  # request never reads as if it were accepted already, and the hold names
  # its limit, the type's approval window.
  defp text(%{stage: :after} = assigns) do
    dgettext(
      "booking",
      "You will receive an email as soon as he confirms or declines the request. Until then, the time is held for you, for up to %{hours} hours.",
      hours: hours(assigns)
    )
  end

  defp text(%{stage: :before, payment_required: true} = assigns) do
    dgettext(
      "booking",
      "%{organizer} confirms each booking personally, so submitting this sends a request rather than booking the time outright. You'll pay now to hold the slot; if %{organizer} declines or doesn't answer in time, you're refunded in full.",
      organizer: host(assigns)
    )
  end

  defp text(assigns) do
    dgettext(
      "booking",
      "Submitting sends a request. The meeting is booked only once %{organizer} confirms it; until he replies, the time is held for you, for up to %{hours} hours.",
      organizer: host(assigns),
      hours: hours(assigns)
    )
  end

  defp hours(%{hours: hours}) when is_integer(hours) and hours > 0, do: hours
  defp hours(_assigns), do: Constraints.default_approval_window_hours()

  # The organiser's name is not always resolvable at every stage; falling back
  # keeps the sentence grammatical rather than leaving a gap where a name goes.
  defp host(%{organizer_name: name}) when is_binary(name) and name != "", do: name
  defp host(_assigns), do: dgettext("booking", "The host")
end
