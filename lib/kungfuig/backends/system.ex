defmodule Kungfuig.Backends.System do
  @moduledoc false

  use Kungfuig.Backend, report: :logger

  defmacro __using__(opts \\ []) do
    Kungfuig.Backend.content(opts)
  end

  @impl Kungfuig.Backend
  def get(meta, key) do
    {:ok,
     meta
     |> Keyword.get(:for, get_kungfuig_env(key))
     |> Enum.reduce(%{}, &Map.put(&2, &1, System.get_env(&1)))}
  end

  defp get_kungfuig_env(key) do
    key = key |> Atom.to_string() |> String.upcase() |> Kernel.<>("_")
    for {k, _} <- System.get_env(), String.starts_with?(k, key), do: k
  end
end
