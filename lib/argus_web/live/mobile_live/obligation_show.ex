defmodule ArgusWeb.MobileLive.ObligationShow do
  use ArgusWeb, :live_view

  alias Argus.Authorization
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Recurrence, Urgency}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:obligations}>
      <div id="mobile-obligation-show">
        <.link
          navigate={~p"/m/#{@current_scope.entity.slug}/obligations"}
          class="text-sm text-base-content/60 flex items-center gap-1"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" /> Obligations
        </.link>

        <div class="mt-2 flex items-start justify-between gap-2">
          <h1 class="text-xl font-semibold">{@obligation.title}</h1>
          <.urgency_badge urgency={@urgency} />
        </div>
        <p class="text-sm text-base-content/60">
          {@obligation.obligation_type.name} · due {format_date(@obligation.due_by)} · {due_label(
            @obligation.due_by,
            @today
          )}
        </p>

        <div class="mt-3 flex flex-wrap gap-1">
          <span class="badge badge-primary badge-soft gap-1">
            <.icon name="hero-user-mini" class="size-3" />{@obligation.primary_assignee.email}
          </span>
          <span :for={c <- @obligation.collaborators} class="badge badge-ghost gap-1">
            {c.user.email}
          </span>
        </div>

        <ol id="event-timeline" class="mt-5 space-y-3">
          <li
            :for={event <- @obligation.events}
            data-status={event.status}
            class="border-l-2 border-base-300 pl-3"
          >
            <div class="flex items-center justify-between">
              <span class="font-medium text-sm">{humanize_status(event.status)}</span>
              <span class="text-xs text-base-content/50">{format_datetime(event.inserted_at)}</span>
            </div>
            <div :if={event.note} class="text-sm text-base-content/70 mt-0.5">{event.note}</div>
          </li>
        </ol>

        <div :if={@live?} class="mt-6 grid grid-cols-1 gap-2">
          <button
            :if={Authorization.can?(@current_scope, :start_progress, @obligation)}
            id="m-start-progress-btn"
            type="button"
            phx-click="start_progress"
            class="btn btn-outline btn-lg"
          >
            Start progress
          </button>
          <button
            :if={Authorization.can?(@current_scope, :mark_done, @obligation)}
            id="m-done-btn"
            type="button"
            phx-click="open_done_modal"
            class="btn btn-primary btn-lg"
          >
            Mark done
          </button>
          <button
            :if={Authorization.can?(@current_scope, :cancel_obligation)}
            id="m-cancel-btn"
            type="button"
            phx-click="cancel"
            class="btn btn-ghost btn-error btn-lg"
          >
            Cancel
          </button>
        </div>
      </div>

      <div :if={@show_done_modal} id="m-done-modal" class="modal modal-bottom modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Mark done</h3>
          <.form for={@done_form} id="m-done-form" phx-submit="complete" class="mt-2 space-y-3">
            <.input
              :if={@recurring?}
              field={@done_form[:next_due_by]}
              type="date"
              label="Next due date"
              required
            />
            <.input
              :if={@obligation.complete_note_required}
              field={@done_form[:note]}
              type="textarea"
              label="Completion note"
              required
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_done_modal">Cancel</button>
              <.button class="btn btn-primary" phx-disable-with="Saving…">Complete</.button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    {:ok, assign(socket, :show_done_modal, false) |> load(id, scope)}
  end

  @impl true
  def handle_event("start_progress", _params, socket) do
    case Obligations.start_progress(socket.assigns.current_scope, socket.assigns.obligation) do
      {:ok, _} -> {:noreply, reload(socket) |> put_flash(:info, "Progress started.")}
      {:error, :not_open} -> {:noreply, put_flash(socket, :error, "Already in progress.")}
      :not_authorise -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("open_done_modal", _params, socket) do
    {:noreply, assign(socket, :show_done_modal, true)}
  end

  def handle_event("close_done_modal", _params, socket) do
    {:noreply, assign(socket, :show_done_modal, false)}
  end

  def handle_event("complete", %{"done" => params}, socket) do
    scope = socket.assigns.current_scope

    attrs = %{note: params["note"], next_due_by: parse_date(params["next_due_by"])}

    case Obligations.complete(scope, socket.assigns.obligation, attrs) do
      {:ok, _completed, _spawned} ->
        {:noreply,
         socket
         |> put_flash(:info, "Obligation completed.")
         |> push_navigate(to: ~p"/m/#{scope.entity.slug}/obligations")}

      {:error, :next_due_required} ->
        {:noreply,
         put_flash(socket, :error, "Next due date is required for recurring obligations.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not complete obligation.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("cancel", _params, socket) do
    scope = socket.assigns.current_scope

    case Obligations.cancel_obligation(scope, socket.assigns.obligation, %{}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Obligation cancelled.")
         |> push_navigate(to: ~p"/m/#{scope.entity.slug}/obligations")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not cancel.")}
    end
  end

  defp load(socket, id, scope) do
    obligation =
      scope
      |> Obligations.get_obligation!(id)
      |> Map.update!(:events, &Enum.sort_by(&1, fn e -> e.inserted_at end, DateTime))

    today = Urgency.today_for(scope.entity.timezone)

    recurring? =
      Recurrence.recurring?(obligation.obligation_type) and is_nil(obligation.series_ended_at)

    socket
    |> assign(:obligation, obligation)
    |> assign(:today, today)
    |> assign(:urgency, Urgency.classify(obligation.obligation_type, obligation.due_by, today))
    |> assign(:live?, live_cycle?(obligation))
    |> assign(:recurring?, recurring?)
    |> assign(
      :done_form,
      to_form(%{"note" => "", "next_due_by" => suggestion(obligation, recurring?)}, as: :done)
    )
  end

  defp reload(socket) do
    load(socket, socket.assigns.obligation.id, socket.assigns.current_scope)
  end

  defp suggestion(obligation, true) do
    case Recurrence.next_due_suggestion(obligation.obligation_type, obligation.due_by) do
      %Date{} = date -> Date.to_iso8601(date)
      _ -> ""
    end
  end

  defp suggestion(_obligation, false), do: ""

  defp live_cycle?(%Obligation{status: "active", completed_at: nil}), do: true
  defp live_cycle?(_), do: false

  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status(status), do: String.capitalize(status)

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
