{
  description = "office_graph development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    openspec.url = "github:Fission-AI/OpenSpec";
  };

  outputs =
    { nixpkgs, openspec, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      agentRuntimeTools =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          openspecCli = openspec.packages.${system}.default;
        in
        pkgs.symlinkJoin {
          name = "office-graph-agent-runtime-tools";
          paths = [
            pkgs.gitMinimal
            openspecCli
          ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram "$out/bin/openspec" --set-default OPENSPEC_TELEMETRY 0
          '';
        };
    in
    {
      packages = forAllSystems (system: {
        agent-runtime-tools = agentRuntimeTools system;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          # Use explicit versions because nixpkgs' BEAM defaults can lag the
          # newest packaged releases for compatibility.
          erlang = pkgs.beam.interpreters.erlang_29;
          elixir = pkgs.beam.packages.erlang_29.elixir_1_20;
          nodejs = pkgs.nodejs_26;
          pnpm = pkgs.pnpm_11;
          dockerClient = pkgs.docker-client;
          dockerCompose = pkgs.docker-compose;
        in
        {
          default = pkgs.mkShell {
            packages = [
              erlang
              elixir
              (agentRuntimeTools system)
              nodejs
              pnpm
              dockerClient
              dockerCompose
              pkgs.zsh
            ];

            shellHook = ''
              export MIX_HOME="''${MIX_HOME:-$PWD/.mix}"
              export HEX_HOME="''${HEX_HOME:-$PWD/.hex}"
              export OPENSPEC_TELEMETRY=''${OPENSPEC_TELEMETRY:-0}
              echo "office_graph dev shell"
              echo "  Erlang:  $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell)"
              echo "  Elixir:  $(elixir --version | tail -n 1)"
              echo "  Node:    $(node --version)"
              echo "  pnpm:    $(pnpm --version)"
              echo "  OpenSpec: $(openspec --version)"
            '';
          };
        }
      );
    };
}
