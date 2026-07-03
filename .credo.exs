%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [
          ~r"/_build/",
          ~r"/deps/"
        ]
      },
      plugins: [
        {ExSlop, []},
        {ExDNA.Credo,
         [
           paths: ["lib/", "test/"],
           min_mass: 60,
           literal_mode: :abstract,
           min_similarity: 0.9,
           normalize_pipes: true,
           excluded_macros: [
             :schema,
             :pipe_through,
             :plug,
             :field,
             :object,
             :input_object,
             :arg,
             :policies,
             :attribute,
             :create_timestamp,
             :update_timestamp,
             :belongs_to,
             :has_many,
             :identity,
             :policy,
             :authorize_if,
             :base_route,
             :index
           ]
         ]}
      ],
      checks: %{
        enabled: [
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Refactor.AppendSingleItem, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.FilterCount, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.UnlessWithElse, []}
        ],
        disabled: [
          {Credo.Check.Design.DuplicatedCode, false}
        ]
      }
    }
  ]
}
