defmodule OfficeGraphTest do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]
end

defmodule OfficeGraphTest.PersistenceFailureResponses do
  @moduledoc false

  def configure!(namespace, responses) when is_atom(namespace) and is_list(responses) do
    Process.put(key(namespace), Map.new(responses))
    :ok
  end

  def clear!(namespace) when is_atom(namespace) do
    Process.put(key(namespace), %{})
    :ok
  end

  def fetch(namespace, stage, default \\ :ok) when is_atom(namespace) and is_atom(stage) do
    namespace
    |> responses_for_process_tree()
    |> Map.get(stage, default)
  end

  defp responses_for_process_tree(namespace) do
    [self() | List.wrap(Process.get(:"$callers"))]
    |> Enum.find_value(%{}, &responses(&1, key(namespace)))
  end

  defp responses(pid, key) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        case List.keyfind(dictionary, key, 0) do
          {^key, responses} -> responses
          nil -> nil
        end

      nil ->
        nil
    end
  end

  defp key(namespace), do: {__MODULE__, namespace}
end
