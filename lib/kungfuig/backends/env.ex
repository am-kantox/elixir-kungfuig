defmodule Kungfuig.Backends.Env do
  @moduledoc false

  use Kungfuig.Backend, report: :logger

  defmacro __using__(opts \\ []) do
    Kungfuig.Backend.content(opts)
  end

  @impl Kungfuig.Backend
  def get(meta, key) do
    {:ok,
     meta
     |> Keyword.get(:for, [key])
     |> Enum.reduce(%{}, &Map.put(&2, &1, Application.get_all_env(&1)))}
  end
end
