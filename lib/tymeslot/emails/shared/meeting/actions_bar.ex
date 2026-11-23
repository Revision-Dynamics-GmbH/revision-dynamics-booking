defmodule Tymeslot.Emails.Shared.Meeting.ActionsBar do
  @moduledoc """
  The reschedule / cancel action row for meeting emails.

  Rendered as a compact row of text links separated by a middle dot so the
  primary CTA (e.g. the join button) stays visually dominant. Each action's
  colour is determined by its `:style` and the surrounding email intent.
  """

  alias Tymeslot.Emails.Shared.{Sanitise, Styles, Text}
  alias Tymeslot.Emails.Shared.Styles.Tokens

  @type button_spec :: %{
          required(:text) => String.t(),
          required(:url) => String.t() | nil,
          optional(:style) => atom(),
          optional(:opts) => keyword()
        }

  @doc """
  The actions that can be offered: those whose URL is present and safe to
  link (`Sanitise.safe_url?/1`). An action without one is left out rather
  than linked to nowhere.
  """
  @spec available(list(button_spec())) :: list(button_spec())
  def available(actions), do: Enum.filter(actions, &Sanitise.safe_url?(&1.url))

  @doc """
  Renders the actions bar for the supplied intent. Link colour per action:
  `:primary` inherits the email intent's deep accent, `:danger` uses the
  cancelled intent (always rose), `:secondary` uses muted ink.

  Only the `available/1` actions are rendered; with none, the bar renders
  nothing.
  """
  @spec meeting_actions_bar(Tokens.intent(), list(button_spec())) :: String.t()
  def meeting_actions_bar(intent, actions) when is_atom(intent) and is_list(actions) do
    case available(actions) do
      [] -> ""
      offered -> bar(intent, nil, offered)
    end
  end

  @doc """
  The actions bar under a section title, or nothing at all when no action is
  available: a heading such as "Need to make changes?" over an empty row
  would promise actions the email does not offer.

  Revision Dynamics (rd-mail-brand.patch): the title and the links form one
  left-aligned sentence, as the shared mail design's secondary links do
  ("Need to make changes? Reschedule · Cancel appointment").

  Options: `:footer`, a note rendered under the bar, and only with it.
  """
  @spec actions_section(Tokens.intent(), String.t(), list(button_spec()), keyword()) ::
          String.t()
  def actions_section(intent, title, actions, opts \\ []) when is_atom(intent) do
    case available(actions) do
      [] ->
        ""

      offered ->
        """
        #{bar(intent, title, offered)}

        #{footer(Keyword.get(opts, :footer))}
        """
    end
  end

  defp footer(nil), do: ""

  defp footer(note),
    do: Text.centered_text(note, font_size: "15px", padding: "8px 0 0 0")

  defp bar(intent, title, actions) do
    separator = ~s(<span style="color: #{Styles.ink_muted()}; padding: 0 8px;">·</span>)

    links =
      Enum.map_join(actions, separator, fn action ->
        safe_text = Sanitise.sanitize_for_email(action.text)
        safe_url = Sanitise.sanitize_url(action.url)
        color = action_link_color(intent, Map.get(action, :style, :primary))

        ~s(<a href="#{safe_url}" style="color: #{color}; text-decoration: underline; font-weight: 500;">#{safe_text}</a>)
      end)

    lead =
      case title do
        nil -> ""
        title -> Sanitise.sanitize_for_email(title) <> " "
      end

    """
    <mj-section padding="20px 0 4px 0">
      <mj-column>
        <mj-text
          align="left"
          font-size="#{Styles.font_size(:md)}"
          line-height="1.6"
          color="#{Styles.ink_soft()}"
          css-class="mobile-text"
        >
          #{lead}#{links}
        </mj-text>
      </mj-column>
    </mj-section>
    """
  end

  # Revision Dynamics: every secondary link reads in the product tone's text
  # colour; cancelling is a calm link, not an alarm.
  @spec action_link_color(Tokens.intent(), :primary | :secondary | :danger | atom()) ::
          String.t()
  defp action_link_color(_intent, _style), do: Tokens.tone().accent_deep
end
