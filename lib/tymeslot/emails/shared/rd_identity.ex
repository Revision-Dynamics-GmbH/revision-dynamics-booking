defmodule Tymeslot.Emails.Shared.RdIdentity do
  @moduledoc """
  Revision Dynamics (rd-mail-brand.patch): who sends these emails, as every
  email's head and foot state it.

  The company data is the imprint of revisiondynamics.com
  (`app/[locale]/imprint/page.tsx` and `messages/*.json` → `imprint` in the
  website repository, as of 23 November 2026). Change it there first, then
  here. The design is the shared Revision Dynamics mail design (README in
  `~/outputs/mail-design-2026-11-23/`): the wordmark at the head, the
  company, register and VAT details, contact, imprint and privacy links at
  the foot, and, for Tymeslot alone, one quiet line with the free source code
  the AGPL asks a network service to offer.

  Nothing here reaches a third party: the wordmark and the web fonts load
  from Revision Dynamics' own hosts, never from Google.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Emails.Shared.Styles.Tokens

  @site "https://revisiondynamics.com"
  @logo_base "https://revisiondynamics.com/logo/brand"

  @company "Revision Dynamics GmbH"
  @street "Schulstraße 27"
  @city "65824 Schwalbach am Taunus"
  @register_number "HRB 12352"
  @managing_director "Tim Thielmann"
  @vat_id "DE459197886"
  @phone_display "+49 160 228 8800"
  @phone_href "tel:+491602288800"
  @contact_email "tim.thielmann@revisiondynamics.com"

  # The public repository of the version this instance runs: Tymeslot
  # v1.46.0 with Revision Dynamics' patches. `RD_SOURCE_URL` overrides it.
  @default_source_url "https://github.com/Revision-Dynamics-GmbH/revision-dynamics-booking"

  @doc "The website's address in the email's language: `/de` or `/en`."
  @spec site_url(String.t() | nil) :: String.t()
  def site_url(locale \\ current_locale()), do: "#{@site}/#{site_locale(locale)}"

  @doc "The imprint in the email's language."
  @spec imprint_url(String.t() | nil) :: String.t()
  def imprint_url(locale \\ current_locale()), do: "#{site_url(locale)}/imprint"

  @doc "The privacy policy in the email's language."
  @spec privacy_url(String.t() | nil) :: String.t()
  def privacy_url(locale \\ current_locale()), do: "#{site_url(locale)}/privacy-policy"

  @doc """
  The website's page for an individual appointment request in the email's
  language (rd-request-fields.patch): where a declined or lapsed request is
  asked anew.
  """
  @spec request_url(String.t() | nil) :: String.t()
  def request_url(locale \\ current_locale()), do: "#{site_url(locale)}/termine/individuell"

  @doc """
  A link into the website, moved to the language of the current page
  (rd-legal-locale.patch). The organiser's legal links are stored once and
  point at `/de/…`; an English booking page shows them as `/en/…`. Links
  elsewhere are returned unchanged.
  """
  @spec localize_site_link(String.t() | nil) :: String.t() | nil
  def localize_site_link(url) when is_binary(url) do
    pattern = Regex.compile!("^" <> Regex.escape(@site) <> "/(?:de|en)(/.*)?$")

    case Regex.run(pattern, url) do
      [_whole] -> site_url()
      [_whole, rest] -> site_url() <> rest
      _other -> url
    end
  end

  def localize_site_link(url), do: url

  @doc "The wordmark for light surfaces (black lettering)."
  @spec wordmark_light_url() :: String.t()
  def wordmark_light_url, do: "#{@logo_base}/revision-dynamics-wordmark-on-light.png"

  @doc "The wordmark for dark surfaces (white lettering)."
  @spec wordmark_dark_url() :: String.t()
  def wordmark_dark_url, do: "#{@logo_base}/revision-dynamics-wordmark.png"

  @doc "The address of the corresponding source the AGPL notice names."
  @spec source_url() :: String.t()
  def source_url do
    case System.get_env("RD_SOURCE_URL") do
      url when is_binary(url) and url != "" -> url
      _unset -> @default_source_url
    end
  end

  @doc "Contact e-mail address shown at the foot."
  @spec contact_email() :: String.t()
  def contact_email, do: @contact_email

  @doc "Display name used where the instance would say \"Tymeslot\"."
  @spec company_short() :: String.t()
  def company_short, do: "Revision Dynamics"

  @doc """
  The head of every email: the wordmark, linked to the website.

  The light wordmark sits on a white plate drawn as a background image,
  which Gmail's forced dark mode leaves alone, so the black lettering stays
  legible there. Clients that honour `prefers-color-scheme` clear the plate
  and show the white wordmark instead (`CSS.dark_mode_styles/0`).
  """
  @spec header_mjml() :: String.t()
  def header_mjml do
    alt = company_short()

    """
    <mj-section padding="28px 8px 20px 8px" background-color="#{Tokens.canvas()}" css-class="rd-canvas rd-head">
      <mj-column>
        <mj-text padding="0" align="left">
          <a href="#{site_url()}" style="text-decoration: none; display: inline-block;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse: separate;"><tr>
              <td class="rd-plate" bgcolor="#ffffff" style="background-image: linear-gradient(#ffffff, #ffffff); border-radius: 8px; padding: 6px 8px;">
                <img class="rd-logo-light" src="#{wordmark_light_url()}" width="140" height="49" alt="#{alt}" style="display: block; width: 140px; height: 49px; border: 0; font-family: Arial, sans-serif; font-size: 16px; font-weight: 600; color: #{Tokens.ink()};" />
                <!--[if !mso]><!-->
                <div class="rd-logo-dark" style="display: none; max-height: 0; overflow: hidden; mso-hide: all;">
                  <img src="#{wordmark_dark_url()}" width="140" height="49" alt="#{alt}" style="display: block; width: 140px; height: 49px; border: 0; font-family: Arial, sans-serif; font-size: 16px; font-weight: 600; color: #f1f6fc;" />
                </div>
                <!--<![endif]-->
              </td>
            </tr></table>
          </a>
        </mj-text>
      </mj-column>
    </mj-section>
    """
  end

  @typedoc """
  Who an email is for. `:guest` is the person who booked and anyone they
  invited: their foot says how to ask a question and why they got the email.
  `:host` is Tim and every account email: internal, so the foot keeps only
  the company, the links and the source notice. `:requester` is a guest
  whose appointment is still a request (request received, not confirmed,
  expired; rd-request-fields.patch): the guest's foot, saying they
  requested an appointment rather than booked one.
  """
  @type audience :: :guest | :host | :requester

  @doc """
  The foot of every email, below the card on the canvas: for a guest a line
  on how to ask, then company and register details, imprint and privacy
  links, why the email was sent and the AGPL source notice; for the host the
  same without the question line and the reason.

  The section carries `rd-foot--<audience>`, by which `footer_for/2` picks
  the matching plain-text foot.
  """
  @spec footer_mjml(audience()) :: String.t()
  def footer_mjml(audience \\ :guest) do
    link_style = "color: #{Tokens.ink_muted()}; text-decoration: underline; white-space: nowrap;"

    link = fn href, label ->
      ~s(<a href="#{href}" class="rd-muted" style="#{link_style}">#{label}</a>)
    end

    paragraphs =
      [
        audience in [:guest, :requester] &&
          dgettext("emails", "Questions? Simply reply to this email or call %{phone}.",
            phone: link.(@phone_href, @phone_display)
          ),
        Enum.join(company_lines(), "<br />"),
        Enum.join(
          [
            link.(imprint_url(), dgettext("emails", "Imprint")),
            link.(privacy_url(), dgettext("emails", "Privacy policy")),
            link.(site_url(), "revisiondynamics.com")
          ],
          " · "
        ),
        reason(audience),
        source_notice(link.(source_url(), dgettext("emails", "Source code of our version")))
      ]

    body =
      paragraphs
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&~s(<p style="margin: 0 0 12px 0;">#{&1}</p>))
      |> Enum.join("\n")

    """
    <mj-section padding="28px 8px 40px 8px" background-color="#{Tokens.canvas()}" css-class="rd-canvas rd-foot rd-foot--#{audience}">
      <mj-column>
        <mj-text
          font-family="#{Tokens.font_family()}"
          font-size="#{Tokens.font_size(:xs)}"
          line-height="1.6"
          color="#{Tokens.ink_muted()}"
          align="left"
          padding="0"
          css-class="rd-muted"
        >
          #{body}
        </mj-text>
      </mj-column>
    </mj-section>
    """
  end

  @doc """
  The same foot as plain text, with every link written out in full.
  `Tymeslot.Emails.Shared.MjmlEmail.base_email/1` stashes both audiences'
  versions; `Tymeslot.Emails.Delivery` appends the one the HTML used.
  """
  @spec footer_text(audience()) :: String.t()
  def footer_text(audience \\ :guest) do
    [
      "--",
      audience in [:guest, :requester] &&
        dgettext("emails", "Questions? Simply reply to this email or call %{phone}.",
          phone: @phone_display
        ) <> "\n",
      Enum.join(company_lines(), "\n") <> "\n",
      "#{dgettext("emails", "Imprint")}: #{imprint_url()}",
      "#{dgettext("emails", "Privacy policy")}: #{privacy_url()}\n",
      reason(audience),
      source_notice("#{dgettext("emails", "Source code of our version")}: #{source_url()}")
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  The audience whose foot an HTML body carries (`footer_mjml/1`), `:guest`
  when it carries none.
  """
  @spec footer_audience(String.t() | nil) :: audience()
  def footer_audience(html) when is_binary(html) do
    cond do
      String.contains?(html, "rd-foot--host") -> :host
      String.contains?(html, "rd-foot--requester") -> :requester
      true -> :guest
    end
  end

  def footer_audience(_html), do: :guest

  # Why the email was sent: a booked appointment, or one only requested
  # (rd-request-fields.patch). Tim's own emails give no reason.
  defp reason(:guest),
    do:
      dgettext(
        "emails",
        "You are receiving this email because you booked an appointment on revisiondynamics.com."
      )

  defp reason(:requester),
    do:
      dgettext(
        "emails",
        "You are receiving this email because you requested an appointment on revisiondynamics.com."
      )

  defp reason(:host), do: false

  # The AGPL notice. Worded under Tymeslot's trademark rules (TRADEMARK.md):
  # an adapted version is "based on" Tymeslot and never presents itself as
  # Tymeslot; the link offers the source of this version (`source_url/0`).
  defp source_notice(link) do
    dgettext(
      "emails",
      "The booking service is based on Tymeslot, free software under the AGPL-3.0. %{link}",
      link: link
    )
  end

  defp company_lines do
    [
      "#{@company} · #{@street} · #{@city}",
      dgettext(
        "emails",
        "Local Court (Amtsgericht) Königstein im Taunus, %{register} · Managing Director: %{director} · VAT ID %{vat}",
        register: @register_number,
        director: @managing_director,
        vat: @vat_id
      )
    ]
  end

  defp current_locale, do: Gettext.get_locale(TymeslotWeb.Gettext)

  defp site_locale("de" <> _rest), do: "de"
  defp site_locale(_other), do: "en"
end
