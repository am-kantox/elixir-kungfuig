defmodule Kungfuig.Backends.System do
  @moduledoc false

  use Kungfuig.Backend

  @prefix Application.compile_env(:kungfuig, :system_env_prefix, "KUNGFUIG_")

  @impl Kungfuig.Backend
  def get(meta) do
    {:ok,
     meta
     |> Keyword.get(:for, get_kungfuig_env())
     |> Enum.reduce(%{}, &Map.put(&2, &1, System.get_env(&1)))}
  end

  defp get_kungfuig_env do
    for {k, _} <- System.get_env(), String.starts_with?(k, @prefix), do: k
  end
end
