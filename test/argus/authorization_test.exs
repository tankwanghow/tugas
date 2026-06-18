defmodule Argus.AuthorizationTest do
  use Argus.DataCase, async: true

  alias Argus.Authorization
  alias Argus.Obligations.Obligation

  import Argus.AccountsFixtures
  import Argus.EntitiesFixtures

  describe "can?/2" do
    test "manager can create obligation" do
      scope = manager_scope_fixture()
      assert Authorization.can?(scope, :create_obligation)
    end

    test "member cannot cancel obligation" do
      scope = member_scope_fixture()
      refute Authorization.can?(scope, :cancel_obligation)
    end

    test "admin can manage entity" do
      scope = entity_scope_fixture()
      assert Authorization.can?(scope, :manage_entity)
    end

    test "manager cannot manage entity" do
      scope = manager_scope_fixture()
      refute Authorization.can?(scope, :manage_entity)
    end

    test "manager can manage types" do
      scope = manager_scope_fixture()
      assert Authorization.can?(scope, :manage_types)
    end

    test "member cannot manage types" do
      scope = member_scope_fixture()
      refute Authorization.can?(scope, :manage_types)
    end
  end

  describe "can?/3" do
    test "collaborator cannot mark done" do
      {scope, obligation} = collaborator_scope_fixture()
      refute Authorization.can?(scope, :mark_done, obligation)
    end

    test "primary assignee member can mark done" do
      {scope, obligation} = primary_assignee_scope_fixture()
      assert Authorization.can?(scope, :mark_done, obligation)
    end

    test "collaborator can start progress" do
      {scope, obligation} = collaborator_scope_fixture()
      assert Authorization.can?(scope, :start_progress, obligation)
    end

    test "non-assignee member cannot start progress" do
      scope = member_scope_fixture()
      other = user_fixture()

      obligation = %Obligation{
        primary_assignee_id: other.id,
        collaborators: []
      }

      refute Authorization.can?(scope, :start_progress, obligation)
    end

    test "member cannot mark done on unassigned obligation" do
      scope = member_scope_fixture()

      obligation = %Obligation{
        primary_assignee_id: nil,
        collaborators: []
      }

      refute Authorization.can?(scope, :mark_done, obligation)
    end

    test "manager can mark done on unassigned obligation" do
      scope = manager_scope_fixture()

      obligation = %Obligation{
        primary_assignee_id: nil,
        collaborators: []
      }

      assert Authorization.can?(scope, :mark_done, obligation)
    end
  end

  describe "mark_completed_in_error" do
    test "admin and manager may, member may not" do
      assert Authorization.can?(entity_scope_fixture(), :mark_completed_in_error)
      assert Authorization.can?(manager_scope_fixture(), :mark_completed_in_error)
      refute Authorization.can?(member_scope_fixture(), :mark_completed_in_error)
    end
  end

  defp collaborator_scope_fixture do
    admin_scope = entity_scope_fixture()
    collaborator = user_fixture()

    %Argus.Entities.Membership{
      user_id: collaborator.id,
      entity_id: admin_scope.entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Argus.Entities.Membership.changeset(%{})
    |> Argus.Repo.insert!()

    membership = Argus.Entities.get_membership!(collaborator, admin_scope.entity)

    scope =
      Argus.Accounts.Scope.put_entity(
        Argus.Accounts.Scope.for_user(collaborator),
        admin_scope.entity,
        membership
      )

    primary = user_fixture()

    obligation = %Obligation{
      primary_assignee_id: primary.id,
      collaborators: [%{user_id: collaborator.id}]
    }

    {scope, obligation}
  end

  defp primary_assignee_scope_fixture do
    scope = member_scope_fixture()

    obligation = %Obligation{
      primary_assignee_id: scope.user.id,
      collaborators: []
    }

    {scope, obligation}
  end
end
