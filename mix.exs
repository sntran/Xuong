defmodule World.MixProject do
  use Mix.Project

  def project do
    [
      app: :world,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      # The core of Wings 3D (wings/, scripts/wings.sh). The parse
      # transform of its texts (intl_tools) compiles first.
      erlc_paths: ["wings/intl_tools", "wings/e3d", "wings/src"],
      erlc_include_path: "wings/src",
      erlc_options: [{:i, ~c"wings/src"}, {:i, ~c"wings/e3d"}, {:i, ~c"wings/intl_tools"}, :nowarn_export_all],
      deps: deps(),
      # The release for the Worker (scripts/edge.sh): the WebAssembly
      # runtime of beam.com has its own ERTS.
      # The files of the catalog (priv/models) are static files of the
      # site: the VM does not read them, so the release has none.
      releases: [
        world: [include_erts: System.get_env("RELEASE_ERTS") != "false", steps: [:assemble, &no_models/1]]
      ],
      aliases: aliases(),
      test_coverage: [
        summary: [threshold: 100],
        # The copy of Wings 3D has its own tests upstream.
        ignore_modules: [~r/^:?(wings_|e3d|tools$|trace_2d$)/, World.GLBHelper]
      ]
    ]
  end

  def cli, do: [preferred_envs: [precommit: :test]]

  def application, do: [mod: {World.Application, []}, extra_applications: [:logger, :crypto]]

  defp deps do
    [
      {:bandit, "~> 1.14"},
      {:plug, "~> 1.20"},
      {:stream_data, "~> 1.4", only: [:dev, :test]},
      # The order flow of the world in TLA+ (specs/): its model check with
      # the native checker of Accord (no Java), and the replay of the log
      # of a run (the branch feat/native-tla-checker).
      {:accord,
       github: "sntran/accord", ref: "8de06a28c098800ccb57e203b8e199c9dec106d6", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [precommit: ["compile --warnings-as-errors", "format", "test --cover"]]
  end

  defp no_models(release) do
    File.rm_rf!(Path.join([release.path, "lib", "world-#{release.version}", "priv", "models"]))
    release
  end
end
