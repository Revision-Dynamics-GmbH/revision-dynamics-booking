defmodule Tymeslot.Emails.Shared.RdIdentityTest do
  @moduledoc """
  Revision Dynamics (rd-mail-brand.patch): the source code notice at the foot
  of every email. Tymeslot's trademark policy lets a modified version say it
  is based on Tymeslot, never call itself Tymeslot, so the wording is fixed
  here, and the link must reach the public repository of this version.
  """
  # Touches the process environment (RD_SOURCE_URL) and the Gettext locale.
  use ExUnit.Case, async: false

  alias Tymeslot.Emails.Shared.RdIdentity

  @repo "https://github.com/Revision-Dynamics-GmbH/revision-dynamics-booking"

  setup do
    previous_url = System.get_env("RD_SOURCE_URL")
    previous_locale = Gettext.get_locale(TymeslotWeb.Gettext)
    System.delete_env("RD_SOURCE_URL")

    on_exit(fn ->
      if previous_url,
        do: System.put_env("RD_SOURCE_URL", previous_url),
        else: System.delete_env("RD_SOURCE_URL")

      Gettext.put_locale(TymeslotWeb.Gettext, previous_locale)
    end)
  end

  test "links the public repository when RD_SOURCE_URL is unset" do
    assert RdIdentity.source_url() == @repo
  end

  test "RD_SOURCE_URL overrides the link, an empty value does not" do
    System.put_env("RD_SOURCE_URL", "https://example.com/rd-booking")
    assert RdIdentity.source_url() == "https://example.com/rd-booking"

    System.put_env("RD_SOURCE_URL", "")
    assert RdIdentity.source_url() == @repo
  end

  for audience <- [:guest, :host] do
    test "German #{audience} foot says the service is based on Tymeslot" do
      Gettext.put_locale(TymeslotWeb.Gettext, "de")

      assert RdIdentity.footer_text(unquote(audience)) =~
               "Die Terminbuchung basiert auf Tymeslot, freie Software unter der AGPL-3.0. " <>
                 "Quellcode unserer Fassung: #{@repo}"

      html = RdIdentity.footer_mjml(unquote(audience))
      assert html =~ "Die Terminbuchung basiert auf Tymeslot, freie Software unter der AGPL-3.0."
      assert html =~ ~s(href="#{@repo}")
      assert html =~ "Quellcode unserer Fassung"
    end

    test "English #{audience} foot says the service is based on Tymeslot" do
      Gettext.put_locale(TymeslotWeb.Gettext, "en")

      assert RdIdentity.footer_text(unquote(audience)) =~
               "The booking service is based on Tymeslot, free software under the AGPL-3.0. " <>
                 "Source code of our version: #{@repo}"

      html = RdIdentity.footer_mjml(unquote(audience))
      assert html =~ "The booking service is based on Tymeslot, free software under the AGPL-3.0."
      assert html =~ "Source code of our version"
    end
  end

  test "Tymeslot appears in the foot only in the source notice" do
    for locale <- ["de", "en"], audience <- [:guest, :host] do
      Gettext.put_locale(TymeslotWeb.Gettext, locale)

      for foot <- [RdIdentity.footer_text(audience), RdIdentity.footer_mjml(audience)] do
        assert length(Regex.scan(~r/Tymeslot/, foot)) == 1
      end
    end
  end
end
