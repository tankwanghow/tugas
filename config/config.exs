# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :argus, :scopes,
  user: [
    default: true,
    module: Argus.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Argus.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

workspace_assets_config = Path.expand("../../shared_config/assets.exs", __DIR__)

if File.exists?(workspace_assets_config) do
  import_config workspace_assets_config
else
  config :esbuild, version: "0.28.1"
  config :tailwind, version: "4.3.1"
end

config :argus,
  ecto_repos: [Argus.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :argus, :upload_limits,
  image: 5_000_000,
  video: 10_000_000,
  pdf: 20_000_000,
  other: 20_000_000

config :argus, :upload_client_image_resize,
  max_edge: 1920,
  quality: 85,
  min_bytes: 50_000

# Configure the endpoint
config :argus, ArgusWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ArgusWeb.ErrorHTML, json: ArgusWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Argus.PubSub,
  live_view: [signing_salt: "YvNiaedN"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :argus, Argus.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild
config :esbuild,
  argus: [
    args:
      ~w(js/app.js js/pdf.worker.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind
config :tailwind,
  argus: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Time zone database — needed for `DateTime.now/1` and entity-timezone urgency badges.
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
