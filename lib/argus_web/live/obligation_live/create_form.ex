defmodule ArgusWeb.ObligationLive.CreateForm do
  @moduledoc """
  Shared new-obligation form logic for the Desktop (`ObligationLive.Form`) and
  Mobile (`MobileLive.ObligationForm`) LiveViews. The two differ only in render
  (layout/shell) and in the post-create redirect path; everything else — option
  loading, validation, and create — lives here. Files are attached later from the
  duty page, not at creation time.
  """
  use ArgusWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias Argus.Entities
  alias Argus.Obligations
  alias Argus.Obligations.Obligation
  alias Argus.Todos

  @obligation_title_max 60

  @doc "Assigns `:type_options`, `:member_options`, and the empty `:form`."
  def load_form(socket, params \\ %{}) do
    scope = socket.assigns.current_scope
    changeset = obligation_changeset(scope, params)

    socket
    |> assign(:type_options, type_options(scope))
    |> assign(:member_options, member_options(scope))
    |> assign(:from_todo_id, params["from_todo"])
    |> assign_form(changeset)
  end

  @doc "Re-runs the changeset for live validation feedback."
  def validate(socket, params) do
    changeset =
      %Obligation{}
      |> Obligations.change_obligation(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @doc """
  Creates the obligation, then redirects to `redirect_path.(scope, obligation)`
  on success.
  """
  def save(socket, params, redirect_path) when is_function(redirect_path, 2) do
    scope = socket.assigns.current_scope

    case Obligations.create_obligation(scope, map_create_params(params)) do
      {:ok, obligation} ->
        socket =
          socket
          |> maybe_record_escalation(scope, obligation)
          |> put_flash(:info, flash_message(socket.assigns[:from_todo_id]))
          |> push_navigate(to: redirect_path.(scope, obligation))

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "An open note is required.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "obligation"))
  end

  defp obligation_changeset(scope, %{"from_todo" => todo_id}) when is_binary(todo_id) do
    case Todos.get_todo_for_escalation(scope, todo_id) do
      {:ok, todo} ->
        %Obligation{}
        |> Obligations.change_obligation(%{
          title: truncate_title(todo.title),
          open_note: "Escalated from todo: #{todo.title}"
        })

      _ ->
        %Obligation{} |> Obligations.change_obligation(%{})
    end
  end

  defp obligation_changeset(_scope, _params) do
    %Obligation{} |> Obligations.change_obligation(%{})
  end

  defp maybe_record_escalation(socket, scope, obligation) do
    case socket.assigns[:from_todo_id] do
      todo_id when is_binary(todo_id) ->
        case Todos.get_todo_for_escalation(scope, todo_id) do
          {:ok, todo} ->
            case Todos.record_escalation(scope, todo, obligation) do
              {:ok, _} ->
                socket

              _ ->
                put_flash(socket, :warning, "Duty created, but the todo could not be linked.")
            end

          _ ->
            socket
        end

      _ ->
        socket
    end
  end

  defp flash_message(nil), do: "Duty created."
  defp flash_message(_), do: "Duty created and todo escalated."

  defp truncate_title(title) when is_binary(title) do
    String.slice(title, 0, @obligation_title_max)
  end

  defp truncate_title(_), do: ""

  defp type_options(scope) do
    Enum.map(Obligations.list_types(scope), &{&1.name, &1.id})
  end

  defp member_options(scope) do
    Entities.list_entity_members(scope.entity)
    |> Enum.map(fn {user, _membership} -> {user.email, user.id} end)
  end

  defp map_create_params(params) do
    params
    |> Map.update("due_by", nil, &parse_date/1)
    |> Map.update("primary_assignee_id", nil, &normalize_assignee/1)
    |> Map.take([
      "title",
      "obligation_type_id",
      "primary_assignee_id",
      "due_by",
      "open_note",
      "collaborator_ids",
      "someday"
    ])
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp normalize_assignee(nil), do: nil
  defp normalize_assignee(""), do: nil
  defp normalize_assignee(id), do: id

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
