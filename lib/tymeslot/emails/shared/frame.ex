defmodule Tymeslot.Emails.Shared.Frame do
  @moduledoc """
  The shared outer MJML scaffold for every email.

  Both the transactional layout (`MjmlEmail.base_mjml_template/2`) and the
  system layout (`Layouts.system_layout/2`) render the same outer shell —
  `<mjml>`, `<mj-head>` with the fonts and CSS, and an `<mj-body>` holding
  the head, the card and the foot. This module owns that scaffold so the two
  layouts only have to supply the sections that go inside.

  Revision Dynamics (rd-mail-brand.patch), following the shared mail design:

      canvas
        head: the Revision Dynamics wordmark        (pre_card)
        card: white, 16px corners, 1px edge in the product tone
          stage: accent rule, eyebrow, title, lead   (stage)
          header                                     (header, usually empty)
          body                                       (body)
        foot: contact, company, imprint, privacy     (footer, on the canvas)

  Sections (all already-rendered MJML strings):

  - `pre_card` — what stands above the card (the wordmark)
  - `stage` — the opening of the card (from `Stage.stage_band/4`)
  - `header` — anything that sits between the stage and the body
  - `body` — the caller's content
  - `footer` — the foot, below the card on the canvas
  """

  alias Tymeslot.Emails.Shared.Styles
  alias Tymeslot.Emails.Shared.Styles.{CSS, Tokens}

  @type sections :: %{
          required(:title) => String.t(),
          required(:preview) => String.t(),
          required(:stage) => String.t(),
          required(:header) => String.t(),
          required(:body) => String.t(),
          required(:footer) => String.t(),
          optional(:pre_card) => String.t()
        }

  @doc "Renders the full MJML document from pre-rendered section strings."
  @spec wrap(sections()) :: String.t()
  def wrap(
        %{
          title: title,
          preview: preview,
          stage: stage,
          header: header,
          body: body,
          footer: footer
        } = sections
      ) do
    pre_card = Map.get(sections, :pre_card, "")
    edge = Tokens.tone().edge

    """
    <mjml>
      <mj-head>
        <mj-title>#{title}</mj-title>
        <mj-preview>#{preview}</mj-preview>
        <mj-raw>
          <meta name="color-scheme" content="light dark" />
          <meta name="supported-color-schemes" content="light dark" />
          <meta name="x-apple-disable-message-reformatting" />
          <meta name="format-detection" content="telephone=no, date=no, address=no, email=no, url=no" />
          #{CSS.font_face_styles()}
          #{Styles.dark_mode_styles()}
        </mj-raw>
        #{Styles.mjml_base_attributes()}
        <mj-breakpoint width="480px" />
        #{Styles.email_css_styles()}
      </mj-head>
      <mj-body background-color="#{Styles.canvas()}" width="600px" css-class="rd-canvas">
        <mj-wrapper
          padding="0 12px 0 12px"
          background-color="#{Styles.canvas()}"
          css-class="rd-canvas"
        >
          #{pre_card}
          <mj-wrapper
            background-color="#{Styles.surface()}"
            border="1px solid #{edge}"
            border-radius="16px"
            padding="0"
            css-class="rd-card"
          >
            #{stage}
            #{header}
            <mj-wrapper
              padding="8px 36px 36px 36px"
              background-color="#{Styles.surface()}"
              border-radius="0 0 15px 15px"
              css-class="rd-body"
            >
              #{body}
            </mj-wrapper>
          </mj-wrapper>
          #{footer}
        </mj-wrapper>
      </mj-body>
    </mjml>
    """
  end
end
