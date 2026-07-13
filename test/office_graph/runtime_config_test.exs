defmodule OfficeGraph.RuntimeConfigTest do
  use ExUnit.Case, async: false

  test "PHX_SERVER enables the endpoint only for exact true values" do
    original = System.get_env("PHX_SERVER")

    on_exit(fn -> restore_env("PHX_SERVER", original) end)

    for {value, expected?} <- [
          {nil, false},
          {"false", false},
          {"0", false},
          {"true", true},
          {"1", true}
        ] do
      restore_env("PHX_SERVER", value)

      runtime_config = Config.Reader.read!("config/runtime.exs", env: :test)
      endpoint_config = runtime_config[:office_graph][OfficeGraphWeb.Endpoint]

      assert Keyword.get(endpoint_config, :server, false) == expected?,
             "expected PHX_SERVER=#{inspect(value)} to set server to #{expected?}"
    end
  end

  test "test database connection accepts explicit worktree isolation settings" do
    env = %{
      "OFFICE_GRAPH_TEST_DATABASE_HOST" => "db.internal",
      "OFFICE_GRAPH_TEST_DATABASE_PORT" => "61234",
      "OFFICE_GRAPH_TEST_DATABASE_USERNAME" => "worker",
      "OFFICE_GRAPH_TEST_DATABASE_PASSWORD" => "secret",
      "OFFICE_GRAPH_TEST_DATABASE_NAME" => "office_graph_ci",
      "MIX_TEST_PARTITION" => "_partition_7"
    }

    originals = Map.new(env, fn {name, _value} -> {name, System.get_env(name)} end)
    on_exit(fn -> Enum.each(originals, fn {name, value} -> restore_env(name, value) end) end)
    Enum.each(env, fn {name, value} -> System.put_env(name, value) end)

    test_config = Config.Reader.read!("config/config.exs", env: :test)
    repo_config = test_config[:office_graph][OfficeGraph.Repo]

    assert repo_config[:hostname] == "db.internal"
    assert repo_config[:port] == 61_234
    assert repo_config[:username] == "worker"
    assert repo_config[:password] == "secret"
    assert repo_config[:database] == "office_graph_ci_partition_7"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
