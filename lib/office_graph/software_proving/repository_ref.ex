defmodule OfficeGraph.SoftwareProving.RepositoryRef do
  @moduledoc false

  use OfficeGraph.SoftwareProving.Resource,
    table: "repository_refs",
    accept: [:repository_id, :name, :ref_type, :target_commit_id, :is_default],
    validations: [ref_type: ~w(branch tag other)]

  attributes do
    attribute :repository_id, :uuid, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :ref_type, :string, allow_nil?: false, public?: true

    attribute :target_commit_id, :uuid, public?: true
    attribute :is_default, :boolean, allow_nil?: false, default: false, public?: true
  end

  relationships do
    belongs_to :repository, OfficeGraph.SoftwareProving.Repository do
      source_attribute :repository_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :target_commit, OfficeGraph.SoftwareProving.Commit do
      source_attribute :target_commit_id
      destination_attribute :id
      define_attribute? false
      public? true
    end
  end

  identities do
    identity :unique_repository_name, [:repository_id, :name]
  end
end
