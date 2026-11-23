defmodule TymeslotWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.Controller
  alias TymeslotWeb.Components.RdPage

  # A branded, self-contained 404 page lives in `error_html/404.html.heex` and is
  # picked up by `embed_templates` as the `render("404.html", assigns)` clause.
  # Every other status falls through to the plain-text clause below.
  embed_templates "error_html/*"

  # The default is to render a plain text page based on
  # the template name. For example, "500.html" becomes
  # "Internal Server Error".
  @spec render(String.t(), map()) :: Phoenix.LiveView.Rendered.t() | String.t()
  def render(template, _assigns) do
    case String.split(template, ".") do
      ["5" <> _rest = status, "html"] -> rd_error_page(status)
      _other -> Controller.status_message_from_template(template)
    end
  end

  # Revision Dynamics (rd-mail-brand.patch): a server error (5xx) renders a
  # page in the website's look instead of a bare status line, naming the
  # status, saying what to do and leading back to the website. Other statuses
  # keep their plain status text, which some callers send as `text/plain`
  # (the 429 of `BookingInvitationController`).
  defp rd_error_page(status) do
    locale = Gettext.get_locale(TymeslotWeb.Gettext)
    site = "https://revisiondynamics.com/" <> RdPage.site_locale(locale)

    assigns = %{
      lang: locale,
      eyebrow: dgettext("errors", "Error %{status}", status: status),
      title: dgettext("errors", "Something went wrong."),
      text: dgettext("errors", "Please try again in a moment. If it happens again, write to us."),
      action_label: dgettext("errors", "Book an appointment"),
      action_href: site <> "/termin",
      secondary_label: dgettext("errors", "Contact"),
      secondary_href: site <> "/contact"
    }

    ~H"""
    <RdPage.page
      lang={@lang}
      eyebrow={@eyebrow}
      title={@title}
      text={@text}
      action_label={@action_label}
      action_href={@action_href}
      secondary_label={@secondary_label}
      secondary_href={@secondary_href}
    />
    """
  end
end
