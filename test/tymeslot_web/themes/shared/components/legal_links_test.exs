defmodule TymeslotWeb.Themes.Shared.Components.LegalLinksTest do
  @moduledoc """
  The footer every booking page carries: a link for each of the organiser's
  legal links that is set, the legal notice first, each opening in a new tab,
  and nothing at all when neither is set.

  Revision Dynamics (rd-mail-brand.patch): a line saying the service is based
  on Tymeslot (AGPL-3.0), with a link to the source of this version, follows
  them and is always there, so the footer always renders.
  """
  use ExUnit.Case, async: true

  @moduletag :themes
  @moduletag :components

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias TymeslotWeb.Themes.Shared.Components.LegalLinks

  @notice "https://example.com/imprint"
  @privacy "https://example.com/privacy"
  @source "https://github.com/Revision-Dynamics-GmbH/revision-dynamics-booking"

  defp render(links) do
    assigns = %{links: links}
    rendered_to_string(~H"<LegalLinks.footer links={@links} />")
  end

  defp anchors(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("footer[data-testid='legal-links'] a")
  end

  test "renders both links in order with new-tab attributes" do
    links = anchors(render(%{legal_notice_url: @notice, privacy_policy_url: @privacy}))

    assert Enum.map(links, &(&1 |> Floki.attribute("href") |> hd())) == [
             @notice,
             @privacy,
             @source
           ]

    assert Enum.map(links, &(&1 |> Floki.text() |> String.trim())) == [
             "Legal notice",
             "Privacy policy",
             "Source code of our version"
           ]

    for link <- links do
      assert Floki.attribute(link, "target") == ["_blank"]
      assert Floki.attribute(link, "rel") == ["noopener noreferrer"]
    end
  end

  test "renders only the link that is set" do
    links = anchors(render(%{legal_notice_url: nil, privacy_policy_url: @privacy}))

    assert Enum.map(links, &Floki.attribute(&1, "href")) == [[@privacy], [@source]]
  end

  test "escapes a URL rather than writing it into the markup" do
    html =
      render(%{
        legal_notice_url: ~s(https://example.com/"><script>x</script>),
        privacy_policy_url: nil
      })

    refute html =~ "<script>"
  end

  test "renders only the source code link when both are nil" do
    links = anchors(render(%{legal_notice_url: nil, privacy_policy_url: nil}))

    assert Enum.map(links, &Floki.attribute(&1, "href")) == [[@source]]
  end

  test "labels the links in German" do
    # The locale is per process, so this test's alone.
    Gettext.put_locale(TymeslotWeb.Gettext, "de")

    links = anchors(render(%{legal_notice_url: @notice, privacy_policy_url: @privacy}))

    assert Enum.map(links, &(&1 |> Floki.text() |> String.trim())) == [
             "Impressum",
             "Datenschutz",
             "Quellcode unserer Fassung"
           ]
  end

  test "renders only the source code link for nil links" do
    assert Enum.map(anchors(render(nil)), &Floki.attribute(&1, "href")) == [[@source]]
  end

  test "points the source code link at RD_SOURCE_URL when it is set" do
    System.put_env("RD_SOURCE_URL", "https://example.com/rd-tymeslot")

    try do
      links = anchors(render(nil))

      assert Enum.map(links, &Floki.attribute(&1, "href")) == [
               ["https://example.com/rd-tymeslot"]
             ]
    after
      System.delete_env("RD_SOURCE_URL")
    end
  end
end
