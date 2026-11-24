import Config

# Configure environment
config :tymeslot, environment: :prod

config :tymeslot, TymeslotWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  session_signing_salt:
    "fG3IVl7dIf6RdFtnyRlEKzAM7rUMDaa5CF04gOsCC+Be0mINFyJLNYKAZj1GDbTdTL7QaZ/+biEC3EGKmi+ATg==",
  live_view: [
    signing_salt:
      "vrKFWytjf6InteaiLuJFILgS9NNY0IZMK+lQtcE5qWV+OfEkgiZGGaSmYwwNfmUcCWcCAnKxNu6gmDRz+Mb7/Q=="
  ]

# Upload directory
config :tymeslot, :upload_directory, "/app/data/uploads"

# Enable secure cookies in production
config :tymeslot, :secure_cookies, true

# Revision Dynamics (24 November 2026): the same day can be booked only until
# 06:00 Berlin time, from then on tomorrow at the earliest
# (`Tymeslot.Utils.TimeRange.same_day_cutoff/1`).
config :tymeslot, :same_day_cutoff, {"Europe/Berlin", 6 * 60}

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Tymeslot.Finch

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Analytics contract validation logs-and-drops in prod instead of raising, so a
# malformed event never crashes a live user flow (it raises in dev/test).
config :tymeslot, :analytics_strict, false

# An email sent outside an email job (see `Tymeslot.Emails.Delivery`) is
# reported and still sent in production while the guard is new; everywhere
# else the default, `:raise`, refuses it.
config :tymeslot, :email_delivery_outside_job, :report
