defmodule ArgusWeb.EntityPicker do
  @moduledoc false
  use ArgusWeb, :html

  attr :memberships, :list, required: true
  attr :form, :any, required: true
  attr :mobile?, :boolean, default: false

  def picker(assigns) do
    ~H"""
    <div id="entity-picker" class="mx-auto max-w-2xl">
      <.header>
        Your entities
        <:subtitle>Pick an entity to enter, or create a new one.</:subtitle>
      </.header>

      <ul id="entities" class="mt-6 divide-y divide-base-300">
        <li
          :for={{entity, membership} <- @memberships}
          id={"entity-#{entity.id}"}
          class="py-3 flex items-center justify-between gap-3"
        >
          <div class="flex items-center gap-2 min-w-0">
            <span class="font-medium truncate">{entity.name}</span>
            <span
              :if={membership.is_default}
              class="badge badge-sm badge-primary shrink-0"
              title="Your default entity"
            >
              Default
            </span>
          </div>
          <.link navigate={enter_path(@mobile?, entity.slug)} class="btn btn-primary btn-sm shrink-0">
            Enter
          </.link>
        </li>
        <li :if={@memberships == []} class="py-6 text-base-content/60">
          No entities yet.
        </li>
      </ul>

      <div class="mt-10">
        <.header>Create an entity</.header>
        <.form
          for={@form}
          id="new-entity-form"
          phx-submit="save"
          phx-change="validate"
          class="mt-4 space-y-3"
        >
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input
            field={@form[:slug]}
            type="text"
            label="Slug"
            class="w-full input font-mono"
            required
            placeholder="lowercase-with-hyphens"
          />
          <.button phx-disable-with="Creating..." class="btn btn-primary w-full sm:w-auto">
            Create entity
          </.button>
        </.form>
      </div>
    </div>
    """
  end

  defp enter_path(true, slug), do: ~p"/m/#{slug}"
  defp enter_path(false, slug), do: ~p"/entities/#{slug}"
end
