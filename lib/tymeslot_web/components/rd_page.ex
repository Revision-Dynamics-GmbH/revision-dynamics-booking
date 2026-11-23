defmodule TymeslotWeb.Components.RdPage do
  @moduledoc """
  Revision Dynamics (rd-mail-brand.patch): the standalone pages a visitor of
  the booking service can meet outside the booking flow (page not found,
  server error, booking not embeddable) in the website's look.

  Self-contained like the pages it replaces: a whole document with inline
  styles, rendered without a layout. The tokens are the website's
  (`app/globals.css`, light and dark following the visitor's system), the
  fonts Outfit and Urbanist from this host's `/fonts/` (`rd-brand.patch`). The
  wordmark is set in type rather than loaded as an image: the service's
  Content-Security-Policy allows images from its own host only, and the page
  must not depend on revisiondynamics.com being reachable.
  """
  use Phoenix.Component

  attr :lang, :string, required: true
  attr :title, :string, required: true
  attr :page_title, :string, default: nil, doc: "the window title; the heading when nil"
  attr :eyebrow, :string, default: nil
  attr :text, :string, default: nil
  attr :action_label, :string, default: nil
  attr :action_href, :string, default: nil
  attr :secondary_label, :string, default: nil
  attr :secondary_href, :string, default: nil
  attr :csp_nonce, :string, default: nil
  attr :robots, :string, default: "noindex"
  attr :compact, :boolean, default: false
  attr :rest, :global
  slot :inner_block

  @spec page(map()) :: Phoenix.LiveView.Rendered.t()
  def page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@lang}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content={@robots} />
        <meta name="color-scheme" content="light dark" />
        <title>{@page_title || @title} · Revision Dynamics</title>
        <link rel="icon" type="image/png" href="/images/rd/icon.png" />
        <style nonce={@csp_nonce}>
          @font-face { font-family: "Outfit"; font-style: normal; font-weight: 100 900; font-display: swap; src: url("/fonts/outfit-latin-wght-normal.woff2") format("woff2"); }
          @font-face { font-family: "Urbanist"; font-style: normal; font-weight: 100 900; font-display: swap; src: url("/fonts/urbanist-latin-wght-normal.woff2") format("woff2"); }
          :root {
            color-scheme: light;
            --rd-bg: #f1f6fc; --rd-stage: radial-gradient(ellipse 85% 36rem at 50% 0%, #ffffff, #f9fbfe 46%, #f1f6fc 90%);
            --rd-card: rgb(255 255 255 / 0.86); --rd-edge: rgb(0 138 170 / 0.48); --rd-hi: rgb(255 255 255 / 0.9);
            --rd-heading: #071832; --rd-text: #263958; --rd-muted: #5b6785;
            --rd-accent: #0a7194; --rd-btn: #0e7490; --rd-btn-ink: #ffffff; --rd-focus: #0b6f94;
            --rd-shadow: 0 18px 48px rgb(15 30 60 / 0.08), 0 2px 6px rgb(15 30 60 / 0.05);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              color-scheme: dark;
              --rd-bg: #010a19; --rd-stage: radial-gradient(ellipse 85% 36rem at 50% 0%, #062538, #03142a 46%, #010a19 90%);
              --rd-card: rgb(3 9 22 / 0.78); --rd-edge: rgb(67 222 255 / 0.32); --rd-hi: rgb(255 255 255 / 0.14);
              --rd-heading: #ffffff; --rd-text: #dbe3f6; --rd-muted: #a9b6d8;
              --rd-accent: #8fe9ff; --rd-btn: #43deff; --rd-btn-ink: #04202a; --rd-focus: #43deff;
              --rd-shadow: 0 24px 70px rgb(0 6 18 / 0.3);
            }
          }
          html, body { margin: 0; min-height: 100%; }
          body {
            min-height: 100vh; box-sizing: border-box; display: flex; flex-direction: column;
            align-items: center; justify-content: center; gap: 28px; padding: 32px 16px;
            background: var(--rd-stage), var(--rd-bg); background-color: var(--rd-bg);
            color: var(--rd-text); font-family: Outfit, "Segoe UI", -apple-system, BlinkMacSystemFont, Roboto, Helvetica, Arial, sans-serif;
            font-size: 16px; line-height: 1.6; -webkit-font-smoothing: antialiased;
          }
          body.rd-compact { background: transparent; gap: 0; padding: 24px 16px; }
          .rd-wordmark {
            color: var(--rd-heading); text-decoration: none; font-family: Urbanist, Outfit, "Segoe UI", sans-serif;
            font-size: 20px; font-weight: 600; letter-spacing: 0; min-height: 44px; display: inline-flex; align-items: center;
          }
          .rd-card {
            width: 100%; max-width: 560px; box-sizing: border-box; padding: 40px 36px;
            border: 1px solid var(--rd-edge); border-radius: 16px; background: var(--rd-card);
            -webkit-backdrop-filter: blur(16px) saturate(1.3); backdrop-filter: blur(16px) saturate(1.3);
            box-shadow: inset 0 1px 0 var(--rd-hi), var(--rd-shadow);
          }
          .rd-compact .rd-card { box-shadow: none; -webkit-backdrop-filter: none; backdrop-filter: none; }
          .rd-eyebrow { margin: 0 0 14px; color: var(--rd-accent); font-size: 13px; font-weight: 500; line-height: 1.2; letter-spacing: 0.14em; text-transform: uppercase; }
          h1 { margin: 0; color: var(--rd-heading); font-family: Urbanist, Outfit, "Segoe UI", sans-serif; font-size: clamp(1.75rem, 1.4rem + 1.5vw, 2.25rem); font-weight: 500; line-height: 1.15; letter-spacing: 0; text-wrap: balance; }
          .rd-text { margin: 16px 0 0; font-size: 18px; line-height: 1.6; }
          .rd-actions { display: flex; flex-wrap: wrap; align-items: center; gap: 12px 20px; margin-top: 28px; }
          .rd-btn {
            display: inline-flex; align-items: center; justify-content: center; min-height: 48px; padding: 0 22px;
            border: 1px solid var(--rd-btn); border-radius: 8px; background: var(--rd-btn); color: var(--rd-btn-ink);
            font-family: Urbanist, Outfit, "Segoe UI", sans-serif; font-size: 17px; font-weight: 600; line-height: 1.1; text-decoration: none;
          }
          .rd-link { color: var(--rd-accent); font-weight: 500; text-underline-offset: 3px; min-height: 44px; display: inline-flex; align-items: center; }
          .rd-btn:focus-visible, .rd-link:focus-visible, .rd-wordmark:focus-visible { outline: 2px solid var(--rd-focus); outline-offset: 3px; border-radius: 8px; }
          @media (max-width: 480px) { .rd-card { padding: 32px 22px; } .rd-text { font-size: 16px; } .rd-btn { width: 100%; } }
        </style>
      </head>
      <body class={@compact && "rd-compact"} {@rest}>
        <a
          :if={!@compact}
          class="rd-wordmark"
          href={"https://revisiondynamics.com/" <> site_locale(@lang)}
        >
          Revision Dynamics
        </a>
        <main class="rd-card">
          <p :if={@eyebrow} class="rd-eyebrow">{@eyebrow}</p>
          <h1>{@title}</h1>
          <p :if={@text} class="rd-text">{@text}</p>
          <div :if={@action_href || @secondary_href} class="rd-actions">
            <a :if={@action_href} class="rd-btn" href={@action_href}>{@action_label}</a>
            <a :if={@secondary_href} class="rd-link" href={@secondary_href}>{@secondary_label}</a>
          </div>
        </main>
        {render_slot(@inner_block)}
      </body>
    </html>
    """
  end

  @doc "The website's language segment for a Gettext locale: `de` or `en`."
  @spec site_locale(String.t() | nil) :: String.t()
  def site_locale("de" <> _rest), do: "de"
  def site_locale(_other), do: "en"
end
