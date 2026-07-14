defmodule OfficeGraph.WorkGraph.RelationshipRegistryTest do
  use OfficeGraph.DataCase, async: true

  alias OfficeGraph.WorkGraph.RelationshipDefinitions

  @canonical_keys ~w(
    contained_in
    decomposes_to
    depends_on
    blocked_by
    generated_from
    requires_check
    satisfied_by
    evidenced_by
    review_finding_for
    discussed_in
    references_external
    affects_scope
  )

  @cycle_forbidden ~w(contained_in decomposes_to depends_on blocked_by)

  test "migration installs the canonical registry without public mutations" do
    assert {:ok, definition} = RelationshipDefinitions.fetch_by_key("review_finding_for")
    assert definition.family == "review"
    assert definition.direction == "directed"
    assert definition.cycle_policy == "allow"

    assert Enum.map(definition.endpoint_rules, &{&1.source_kind, &1.target_kind}) == [
             {"review_finding", "task"}
           ]

    refute function_exported?(OfficeGraph.WorkGraph.Domain, :create_relationship_definition, 1)
  end

  test "migration installs the complete MVP vocabulary and cycle policies" do
    definitions = Enum.map(@canonical_keys, &RelationshipDefinitions.fetch_by_key/1)

    assert Enum.all?(definitions, &match?({:ok, _definition}, &1))

    assert Enum.map(definitions, fn {:ok, definition} ->
             {definition.key, definition.cycle_policy}
           end) ==
             Enum.map(@canonical_keys, fn key ->
               {key, if(key in @cycle_forbidden, do: "forbid", else: "allow")}
             end)
  end

  test "unknown keys fail with a stable error" do
    assert {:error, {:unknown_relationship_definition, "invented"}} =
             RelationshipDefinitions.fetch_by_key("invented")
  end
end
