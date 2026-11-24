defmodule TymeslotWeb.Themes.Shared.Components.BookingForm do
  @moduledoc """
  The booking step's form: name, email, the institution or company (while
  `Tymeslot.Bookings.Institution.field_enabled?/0`, Revision Dynamics) and
  message, with the anti-spam markup every theme's form must carry, in the
  one order the booking submit (`Shared.BookingFlow`) and the reCAPTCHA hook
  expect:

    * the reCAPTCHA hook attributes on the `<form>`
      (`SecurityFields.recaptcha_form_attrs/2`);
    * the honeypot field (`CoreComponents.Forms.honeypot_field/1`, shared
      with every public form), first inside the form;
    * the hidden reCAPTCHA token input, last inside the form;
    * after the form, the inner block (a theme renders the guest field
      there), then the privacy notice, then the reCAPTCHA privacy notice.

  On a meeting type whose bookings are requests the host approves
  (`Tymeslot.Bookings.RequestFields.applies?/1`, Revision Dynamics,
  rd-request-fields.patch), pass `meeting_type`: the form then asks for a
  title and a description (the message field, required, under that label),
  both required, and the institution or company is optional. The labels of
  those fields are the form's own (`request_labels/0`), not a theme's.

  The privacy notice tells the guest who receives their details and links the
  organiser's privacy policy (`privacy_policy_url`, from
  `Profiles.public_legal_links/1`). It is plain text with a link, not a
  consent checkbox: a booking rests on the contract, so the guest is informed
  rather than asked. It renders only when a policy URL is set, and always
  outside the `<form>`, so it sits above the theme's action row.

  The reCAPTCHA pieces render only while booking reCAPTCHA is active.

  A theme varies only what is look, never structure: the form's `class`, a
  `contact_class` wrapping the name and email (Quill lays them side by side),
  the message's `message_rows`, and the field `labels` (defaults below). The
  events are the canonical `validate`, `field_blur` and `submit`
  (`Shared.StepEvents`), sent to `target`, the step component. The `<form>`
  carries the markup contract's `data-fact="attendee"`.
  """

  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  use TymeslotWeb.Components.CoreComponents, only: [honeypot_field: 1, input: 1]

  alias Tymeslot.Bookings.Institution
  alias Tymeslot.Bookings.RequestFields
  alias TymeslotWeb.Live.Shared.FormValidationHelpers
  alias TymeslotWeb.Themes.Shared.SecurityFields

  @label_keys [
    :name,
    :name_placeholder,
    :email,
    :email_placeholder,
    :company,
    :company_placeholder,
    :message,
    :message_placeholder
  ]

  attr :form, Phoenix.HTML.Form, required: true
  attr :validation_errors, :any, required: true
  attr :target, :any, required: true, doc: "the step component (`@myself`)"
  attr :class, :any, default: nil, doc: "classes on the form element"

  attr :contact_class, :any,
    default: nil,
    doc: "when set, name and email sit in a `<div>` with these classes"

  attr :message_rows, :integer, default: 3

  attr :meeting_type, :any,
    default: nil,
    doc: "the type booked; a request type asks for a title and a description"

  attr :labels, :map,
    default: nil,
    doc: "labels and placeholders, keyed #{inspect(@label_keys)}; `default_labels/0` when nil"

  attr :organizer_name, :string,
    default: nil,
    doc: "who receives the details; \"The organiser\" when nil"

  attr :privacy_policy_url, :string,
    default: nil,
    doc: "the organiser's privacy policy; no privacy notice when nil"

  slot :inner_block, doc: "rendered after the form and before the privacy notice"

  @spec booking_form(map()) :: Phoenix.LiveView.Rendered.t()
  def booking_form(assigns) do
    # A theme's own labels may predate the institution field.
    labels =
      Map.merge(
        Map.take(default_labels(), [:company, :company_placeholder]),
        assigns.labels || default_labels()
      )

    request = RequestFields.applies?(assigns.meeting_type)

    labels =
      if request,
        do: Map.merge(labels, request_labels()),
        else: labels

    assigns =
      assigns
      |> assign(:labels, labels)
      |> assign(:institution_field, Institution.field_enabled?())
      |> assign(:request, request)

    ~H"""
    <.form
      :let={f}
      for={@form}
      as={:booking}
      phx-change="validate"
      phx-submit="submit"
      phx-target={@target}
      data-testid="booking-form"
      data-fact="attendee"
      class={@class}
      id="booking-form"
      novalidate
      {SecurityFields.recaptcha_form_attrs("booking_form", "booking")}
    >
      <.honeypot_field id="booking-website" param_root="booking" />

      <div :if={@contact_class} class={@contact_class}>
        <.contact_fields
          f={f}
          labels={@labels}
          validation_errors={@validation_errors}
          target={@target}
        />
      </div>
      <.contact_fields
        :if={!@contact_class}
        f={f}
        labels={@labels}
        validation_errors={@validation_errors}
        target={@target}
      />

      <%!-- Its own row under name and email at every width: it names the
           organiser's calendar entry ("<meeting type> x <institution>"). --%>
      <.input
        :if={@institution_field}
        field={f[:company]}
        label={@labels.company}
        placeholder={@labels.company_placeholder}
        errors={FormValidationHelpers.field_errors(@validation_errors, :company)}
        required={!@request}
        maxlength={Institution.max_length()}
        autocomplete="organization"
        class="booking-form__institution"
        data-testid="booking-institution"
        phx-debounce="blur"
        phx-blur="field_blur"
        phx-value-field="company"
        phx-target={@target}
      />

      <%!-- A request (rd-request-fields.patch): what it is about, in one
           line that names the organiser's calendar entry ("<title> x
           <institution>"), then the description in the message field. --%>
      <.input
        :if={@request}
        field={f[:title]}
        label={@labels.title}
        placeholder={@labels.title_placeholder}
        errors={FormValidationHelpers.field_errors(@validation_errors, :title)}
        required
        maxlength={RequestFields.title_max_length()}
        class="booking-form__request-title"
        data-testid="booking-request-title"
        phx-debounce="blur"
        phx-blur="field_blur"
        phx-value-field="title"
        phx-target={@target}
      />

      <.input
        field={f[:message]}
        type="textarea"
        label={if @request, do: @labels.description, else: @labels.message}
        placeholder={
          if @request, do: @labels.description_placeholder, else: @labels.message_placeholder
        }
        errors={FormValidationHelpers.field_errors(@validation_errors, :message)}
        rows={if @request, do: max(@message_rows, 5), else: @message_rows}
        required={@request}
        maxlength={if @request, do: RequestFields.description_max_length()}
        data-testid={@request && "booking-request-description"}
        phx-debounce="blur"
        phx-blur="field_blur"
        phx-value-field="message"
        phx-target={@target}
      />

      <SecurityFields.recaptcha_token_field id_prefix="booking" param_root="booking" />
    </.form>

    {render_slot(@inner_block)}

    <p :if={@privacy_policy_url} class="booking-privacy-notice" data-testid="booking-privacy-notice">
      {privacy_sentence(@organizer_name)}
      <a href={@privacy_policy_url} target="_blank" rel="noopener noreferrer">
        {dgettext("booking", "Privacy policy")}
      </a>
    </p>

    <SecurityFields.recaptcha_notice_block />
    """
  end

  @doc """
  The privacy policy URL out of the page's `legal_links` assign, for the
  `privacy_policy_url` attribute. `nil` where the page holds no links (a
  preview or a component rendered on its own).
  """
  @spec privacy_policy_url(map() | nil) :: String.t() | nil
  def privacy_policy_url(%{privacy_policy_url: url}),
    do: Tymeslot.Emails.Shared.RdIdentity.localize_site_link(url)
  def privacy_policy_url(_legal_links), do: nil

  defp privacy_sentence(nil),
    do: dgettext("booking", "The organiser uses these details to arrange your meeting.")

  defp privacy_sentence(name),
    do:
      dgettext("booking", "%{organizer} uses these details to arrange your meeting.",
        organizer: name
      )

  @doc "The labels and placeholders a theme that passes none gets."
  @spec default_labels() :: %{atom() => String.t()}
  def default_labels do
    %{
      name: dgettext("booking", "Your Name"),
      name_placeholder: dgettext("booking", "John Doe"),
      email: dgettext("booking", "Email Address"),
      email_placeholder: dgettext("booking", "john@example.com"),
      company: dgettext("booking", "Institution or company"),
      company_placeholder: dgettext("booking", "Enter your institution or company"),
      message: dgettext("booking", "Additional Message (Optional)"),
      message_placeholder: dgettext("booking", "Let me know what you'd like to discuss...")
    }
  end

  @doc """
  The labels and placeholders of a request's form
  (`Tymeslot.Bookings.RequestFields`), the same in every theme: the title,
  the description, and the institution or company marked optional.
  """
  @spec request_labels() :: %{atom() => String.t()}
  def request_labels do
    %{
      company: dgettext("booking", "Institution or company (optional)"),
      title: dgettext("booking", "Title"),
      title_placeholder: dgettext("booking", "What is it about, in a few words?"),
      description: dgettext("booking", "Description"),
      description_placeholder:
        dgettext("booking", "What would you like to discuss? What should be prepared?")
    }
  end

  @doc """
  The short labels and placeholders, in sentence case: "Name", "Email",
  "Institution or company", "Message (optional)". For a theme whose voice
  wants plainer words than `default_labels/0`; pass them as `labels`.
  """
  @spec short_labels() :: %{atom() => String.t()}
  def short_labels do
    %{
      name: dgettext("booking", "Name"),
      name_placeholder: dgettext("booking", "Enter your full name"),
      email: dgettext("booking", "Email"),
      email_placeholder: dgettext("booking", "your.email@example.com"),
      company: dgettext("booking", "Institution or company"),
      company_placeholder: dgettext("booking", "Enter your institution or company"),
      message: dgettext("booking", "Message (optional)"),
      message_placeholder: dgettext("booking", "Add any details...")
    }
  end

  attr :f, Phoenix.HTML.Form, required: true
  attr :labels, :map, required: true
  attr :validation_errors, :any, required: true
  attr :target, :any, required: true

  defp contact_fields(assigns) do
    ~H"""
    <.input
      field={@f[:name]}
      label={@labels.name}
      placeholder={@labels.name_placeholder}
      errors={FormValidationHelpers.field_errors(@validation_errors, :name)}
      required
      phx-debounce="blur"
      phx-blur="field_blur"
      phx-value-field="name"
      phx-target={@target}
    />

    <.input
      field={@f[:email]}
      label={@labels.email}
      type="email"
      placeholder={@labels.email_placeholder}
      errors={FormValidationHelpers.field_errors(@validation_errors, :email)}
      required
      phx-debounce="blur"
      phx-blur="field_blur"
      phx-value-field="email"
      phx-target={@target}
    />
    """
  end
end
