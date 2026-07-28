# Project Agent Instructions

- Use the project Nix flake for all runtime and CLI dependencies. Enter it with `nix --extra-experimental-features 'nix-command flakes' develop` before running project tools.
- The flake intentionally pins explicit package attributes for the current toolchain: Erlang/OTP 29, Elixir 1.20, Node.js 26, OpenSpec, and zsh. Do not replace these with moving aliases such as `pkgs.erlang`, `pkgs.elixir`, or `pkgs.nodejs` unless the user asks to follow nixpkgs defaults.
- Use OpenSpec as the project workflow source of truth.
- Keep durable proposals, designs, implementation tasks, and accepted project
  decisions under `openspec/**`. Do not create `docs/superpowers/**` or another
  parallel planning tree.
- Before planning or implementing behavior changes, check for OpenSpec files in `openspec/`, including `openspec/project.md`, `openspec/specs/`, and `openspec/changes/`.
- Run OpenSpec from inside the Nix shell. Prefer `openspec list`, `openspec show`, and `openspec validate --strict` for spec discovery and verification.
- Prefer built-in Ash and AshPostgres features over direct Ecto and explicit
  `Repo.transaction`. Repository-authored raw SQL requires the user's explicit
  approval for the exact occurrence in an accepted OpenSpec change.
