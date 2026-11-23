defmodule Tymeslot.Emails.Shared.MjmlEmailTest do
  use Tymeslot.DataCase, async: true
  @moduletag :emails

  alias Tymeslot.Emails.Shared.MjmlEmail
  alias Tymeslot.Mailer

  describe "compile_mjml/1" do
    test "compiles valid MJML to HTML" do
      mjml = """
      <mjml>
        <mj-body>
          <mj-section>
            <mj-column>
              <mj-text>Hello World</mj-text>
            </mj-column>
          </mj-section>
        </mj-body>
      </mjml>
      """

      html = MjmlEmail.compile_mjml(mjml)

      assert html =~ "Hello World"
      assert html =~ "<!doctype html>"
    end

    test "raises error on invalid MJML" do
      invalid_mjml = "<mjml><invalid-tag></invalid-tag></mjml>"

      assert_raise RuntimeError, ~r/MJML compilation failed/, fn ->
        MjmlEmail.compile_mjml(invalid_mjml)
      end
    end
  end

  describe "base_email/1" do
    test "creates email with correct from address" do
      email = MjmlEmail.base_email()

      assert %Swoosh.Email{} = email
      assert email.from == {configured(:from_name), configured(:from_email)}
    end

    # Revision Dynamics (rd-mail-brand.patch): the head is the Revision
    # Dynamics wordmark, loaded from revisiondynamics.com, so nothing is
    # attached inline.
    test "attaches nothing; the wordmark is an image URL" do
      email = MjmlEmail.base_email()

      assert email.attachments == []
    end

    test "references the wordmark in the HTML body by its absolute URL" do
      mjml =
        MjmlEmail.base_mjml_template("<mj-text>x</mj-text>", %{intent: :confirmed, eyebrow: "x"})

      assert mjml =~
               "https://revisiondynamics.com/logo/brand/revision-dynamics-wordmark-on-light.png"

      refute mjml =~ "cid:"
    end
  end

  describe "base_email/1 tracking" do
    test "defaults to :transactional" do
      email = MjmlEmail.base_email()

      assert Mailer.tracking(email) == :transactional
    end

    test "stashes :lifecycle when given explicitly" do
      email = MjmlEmail.base_email(tracking: :lifecycle)

      assert Mailer.tracking(email) == :lifecycle
    end

    test "stashes :marketing when given explicitly" do
      email = MjmlEmail.base_email(tracking: :marketing)

      assert Mailer.tracking(email) == :marketing
    end

    test "carries no provider options at build time — translation happens at delivery" do
      email = MjmlEmail.base_email(tracking: :marketing)

      assert email.provider_options == %{}
    end
  end

  describe "fetch_from_email/0" do
    test "returns a valid email address" do
      email = MjmlEmail.fetch_from_email()

      assert email == configured(:from_email)
      assert email =~ ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/
    end
  end

  describe "put_reply_to/3" do
    test "sets Reply-To to the named address" do
      email = MjmlEmail.put_reply_to(MjmlEmail.base_email(), "Jane Host", "jane@example.com")

      assert email.reply_to == {"Jane Host", "jane@example.com"}
    end

    test "trims surrounding whitespace from the address" do
      email = MjmlEmail.put_reply_to(MjmlEmail.base_email(), "Jane", "  jane@example.com \n")

      assert email.reply_to == {"Jane", "jane@example.com"}
    end

    test "leaves From as the instance sender" do
      email = MjmlEmail.put_reply_to(MjmlEmail.base_email(), "Jane Host", "jane@example.com")

      assert email.from == {configured(:from_name), configured(:from_email)}
    end

    test "leaves Reply-To unset when the address is nil" do
      email = MjmlEmail.put_reply_to(MjmlEmail.base_email(), "Jane Host", nil)

      assert email.reply_to == nil
    end

    test "leaves Reply-To unset when the address is blank" do
      email = MjmlEmail.put_reply_to(MjmlEmail.base_email(), "Jane Host", "   ")

      assert email.reply_to == nil
    end

    test "leaves Reply-To unset when the address is the instance sender, in any case" do
      sender = configured(:from_email)

      email =
        MjmlEmail.put_reply_to(MjmlEmail.base_email(), "Instance", " #{String.upcase(sender)} ")

      assert email.reply_to == nil
    end

    # Swoosh stores a bare address as `{"", address}`, which adapters send
    # without a display name.
    test "uses the bare address when the name is nil" do
      email = MjmlEmail.put_reply_to(MjmlEmail.base_email(), nil, "jane@example.com")

      assert email.reply_to == {"", "jane@example.com"}
    end

    test "uses the bare address when the name is blank" do
      email = MjmlEmail.put_reply_to(MjmlEmail.base_email(), "  ", "jane@example.com")

      assert email.reply_to == {"", "jane@example.com"}
    end

    test "strips CR and LF from the name, so it cannot inject a header" do
      email =
        MjmlEmail.put_reply_to(
          MjmlEmail.base_email(),
          "Jane\r\nBcc: evil@example.com",
          "jane@example.com"
        )

      assert email.reply_to == {"Jane Bcc: evil@example.com", "jane@example.com"}
    end
  end

  describe "fetch_from_name/0" do
    test "returns a non-empty string" do
      name = MjmlEmail.fetch_from_name()

      assert name == configured(:from_name)
      assert String.length(name) > 0
    end
  end

  describe "base_mjml_template/2" do
    test "generates valid MJML with organizer details" do
      content = "<mj-text>Test Content</mj-text>"

      organizer_details = %{
        intent: :confirmed,
        eyebrow: "Confirmed"
      }

      mjml = MjmlEmail.base_mjml_template(content, organizer_details)

      assert mjml =~ "<mjml>"
      assert mjml =~ "</mjml>"
      assert mjml =~ "Test Content"
      assert mjml =~ "Tymeslot"
    end

    test "uses provided organizer details" do
      content = "<mj-text>Test</mj-text>"

      organizer_details = %{
        name: "John Doe",
        email: "john@example.com",
        title: "CEO",
        intent: :confirmed,
        eyebrow: "Confirmed"
      }

      mjml = MjmlEmail.base_mjml_template(content, organizer_details)

      # Revision Dynamics (rd-mail-brand.patch): the organiser strip is gone;
      # the name stands in the title when no stage title is given.
      assert mjml =~ "John Doe"
    end

    test "renders no avatar, neither an image nor a data URI" do
      content = "<mj-text>Test</mj-text>"

      organizer_details = %{
        name: "Jane Smith",
        avatar_url: "https://example.com/avatar.jpg",
        intent: :confirmed,
        eyebrow: "Confirmed"
      }

      html =
        content
        |> MjmlEmail.base_mjml_template(organizer_details)
        |> MjmlEmail.compile_mjml()

      refute html =~ "data:image"
      refute html =~ "https://example.com/avatar.jpg"
      assert html =~ "Jane Smith"
    end

    test "includes standard email sections" do
      content = "<mj-text>Body Content</mj-text>"

      organizer_details = %{
        intent: :confirmed,
        eyebrow: "Confirmed"
      }

      mjml = MjmlEmail.base_mjml_template(content, organizer_details)

      # Check for header, content, and footer sections
      assert mjml =~ "<mj-head>"
      assert mjml =~ "<mj-body"
      assert mjml =~ "Revision Dynamics GmbH"
      assert mjml =~ "HRB 12352"
      assert mjml =~ "/privacy-policy"
      assert mjml =~ "Tymeslot, free software under the AGPL-3.0"
    end

    # Revision Dynamics (rd-mail-brand.patch): Outfit and Urbanist come from the
    # booking host itself, never from a third party.
    test "loads web fonts only from the booking host, never from a font service" do
      content = "<mj-text>Test</mj-text>"

      organizer_details = %{
        intent: :confirmed,
        eyebrow: "Confirmed"
      }

      mjml = MjmlEmail.base_mjml_template(content, organizer_details)

      assert mjml =~ ~s(<mj-all font-family="Outfit, 'Segoe UI')
      assert mjml =~ "/fonts/outfit-latin-wght-normal.woff2"
      refute mjml =~ "<mj-font"
      refute mjml =~ "'Inter'"

      # MJML adds a Google Fonts link of its own for a default web font the
      # stack names, so only the compiled HTML shows what an open fetches.
      html = MjmlEmail.compile_mjml(mjml)

      assert html =~ "Roboto"
      refute html =~ "googleapis"
      refute html =~ "gstatic"
    end

    test "escapes ampersand in organizer name exactly once when stage_title is absent" do
      content = "<mj-text>Test</mj-text>"

      organizer_details = %{
        name: "Tom & Jerry",
        intent: :confirmed,
        eyebrow: "Confirmed"
      }

      mjml = MjmlEmail.base_mjml_template(content, organizer_details)

      assert mjml =~ "Tom &amp; Jerry"
      refute mjml =~ "Tom &amp;amp; Jerry"
    end

    test "escapes ampersand in explicit stage_title exactly once" do
      content = "<mj-text>Test</mj-text>"

      organizer_details = %{
        name: "Tom & Jerry",
        stage_title: "R&D",
        intent: :confirmed,
        eyebrow: "Confirmed"
      }

      mjml = MjmlEmail.base_mjml_template(content, organizer_details)

      assert mjml =~ "R&amp;D"
      refute mjml =~ "R&amp;amp;D"
    end
  end

  # Reads the sender identity from config rather than the module under test, so
  # the assertions stay independent of MjmlEmail's own accessors.
  defp configured(key), do: Application.get_env(:tymeslot, :email)[key]
end
