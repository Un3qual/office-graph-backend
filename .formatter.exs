[
  import_deps: [:ash, :ash_postgres, :ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  inputs: [
    "*.{ex,exs}",
    "{config,credo_checks,lib,test}/**/*.{ex,exs}",
    "priv/*/seeds.exs"
  ]
]
