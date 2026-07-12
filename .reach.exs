[
  layers: [
    web: ["OfficeGraphWeb", "OfficeGraphWeb.*"],
    runtime: ["OfficeGraph.Application"],
    data: ["OfficeGraph.Repo"],
    domain: [
      "OfficeGraph",
      "OfficeGraph.AgentRuntime",
      "OfficeGraph.ApiSupport",
      "OfficeGraph.Audit",
      "OfficeGraph.Audit.*",
      "OfficeGraph.Authorization",
      "OfficeGraph.Authorization.*",
      "OfficeGraph.Content",
      "OfficeGraph.Content.*",
      "OfficeGraph.DurableDelivery",
      "OfficeGraph.DurableDelivery.*",
      "OfficeGraph.ExternalRefs",
      "OfficeGraph.ExternalRefs.*",
      "OfficeGraph.Foundation",
      "OfficeGraph.Foundation.*",
      "OfficeGraph.Identity",
      "OfficeGraph.Identity.*",
      "OfficeGraph.Integrations",
      "OfficeGraph.Integrations.*",
      "OfficeGraph.Operations",
      "OfficeGraph.Operations.*",
      "OfficeGraph.OrderedPlacement",
      "OfficeGraph.Projections",
      "OfficeGraph.Projections.*",
      "OfficeGraph.ProposedChanges",
      "OfficeGraph.ProposedChanges.*",
      "OfficeGraph.RawArchives",
      "OfficeGraph.Revisions",
      "OfficeGraph.Revisions.*",
      "OfficeGraph.Runs",
      "OfficeGraph.Runs.*",
      "OfficeGraph.SoftwareProving",
      "OfficeGraph.Tenancy",
      "OfficeGraph.Tenancy.*",
      "OfficeGraph.Tombstones",
      "OfficeGraph.Tombstones.*",
      "OfficeGraph.Verification",
      "OfficeGraph.WorkContainers",
      "OfficeGraph.WorkGraph",
      "OfficeGraph.WorkGraph.*",
      "OfficeGraph.WorkPackets",
      "OfficeGraph.WorkPackets.*"
    ],
    support: ["Mix.Tasks.*"]
  ],
  deps: [
    forbidden: [
      {:domain, :web, except: ["OfficeGraph.Application"]}
    ]
  ],
  calls: [
    forbidden: [
      {"OfficeGraph.*", ["OfficeGraphWeb.*"], except: ["OfficeGraph.Application"]},
      {"OfficeGraph.*", ["Plug.*", "Phoenix.*", "Absinthe.*"],
       except: ["OfficeGraph.DurableDelivery.Subscriptions"]}
    ]
  ],
  source: [
    forbidden_modules: [
      "OfficeGraphWeb.GraphQL.Compatibility.*",
      "OfficeGraphWeb.JsonApi.Compatibility.*"
    ],
    forbidden_files: [
      "lib/office_graph_web/schema.ex",
      "lib/office_graph_web/api/**"
    ]
  ],
  clone_analysis: [
    provider: :ex_dna,
    min_mass: 60,
    min_similarity: 0.9,
    literal_mode: :abstract,
    normalize_pipes: true,
    excluded_macros: [
      :schema,
      :pipe_through,
      :plug,
      :field,
      :object,
      :input_object,
      :policies,
      :policy,
      :authorize_if
    ],
    max_clones: 1
  ],
  smells: [
    strict: true,
    fixed_shape_map: [
      min_keys: 3,
      min_occurrences: 5,
      evidence_limit: 10
    ],
    behaviour_candidate: [
      min_modules: 3,
      min_callbacks: 3,
      module_display_limit: 8,
      callback_display_limit: 8
    ]
  ]
]
