defmodule ArgusWeb.Router do
  use ArgusWeb, :router

  import ArgusWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_cookies
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArgusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug ArgusWeb.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ArgusWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/locale/:locale", LocaleController, :update
  end

  # Other scopes may use custom stacks.
  # scope "/api", ArgusWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:argus, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ArgusWeb do
    pipe_through [:browser, :require_authenticated_user, ArgusWeb.Plugs.AutoRouteByDevice]

    live_session :require_authenticated_user,
      on_mount: [{ArgusWeb.UserAuth, :require_authenticated}, {ArgusWeb.Locale, :default}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/entities", EntityLive.Select, :index
    end

    live_session :entity_scoped,
      on_mount: [
        {ArgusWeb.UserAuth, :require_authenticated},
        {ArgusWeb.UserAuth, :require_entity},
        {ArgusWeb.Locale, :default}
      ] do
      live "/entities/:entity_slug", DashboardLive.Index, :index
      live "/entities/:entity_slug/obligations/new", ObligationLive.Form, :new
      live "/entities/:entity_slug/obligations/:id", ObligationLive.Show, :show
      live "/entities/:entity_slug/obligation-types", ObligationTypeLive.Index, :index
      live "/entities/:entity_slug/members", MembershipLive.Index, :index
      live "/entities/:entity_slug/invite-session/:role", MembershipLive.InviteSession, :show

      live "/m/:entity_slug", MobileLive.Dashboard, :show
      live "/m/:entity_slug/obligations/new", MobileLive.ObligationForm, :new
      live "/m/:entity_slug/obligations/:id", MobileLive.ObligationShow, :show
      live "/m/:entity_slug/invite-session/:role", MobileLive.InviteSession, :show
    end

    post "/users/update-password", UserSessionController, :update_password

    get "/view-mode", ViewModeController, :set
    get "/set-view", ViewModeController, :set

    get "/entities/:entity_slug/obligations/:obligation_id/documents/:id",
        DocumentController,
        :show

    post "/entities/:entity_slug/obligations/:obligation_id/documents",
         DocumentController,
         :create
  end

  scope "/", ArgusWeb do
    pipe_through [:browser, ArgusWeb.Plugs.AutoRouteByDevice]

    live_session :current_user,
      on_mount: [{ArgusWeb.UserAuth, :mount_current_scope}, {ArgusWeb.Locale, :default}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/invitations/:token", InvitationLive.Show, :show
      live "/m/invitations/:token", MobileLive.InvitationShow, :show
    end

    post "/invitations/:token/accept", InvitationController, :accept
    post "/m/invitations/:token/accept", InvitationController, :mobile_accept
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
