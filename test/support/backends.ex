defmodule Kungfuig.Backends.EnvTransform do
  @moduledoc false

  use Kungfuig.Backend, report: :logger, imminent: true

  @impl Kungfuig.Backend
  def get(meta, key) do
    {:ok,
     meta
     |> Keyword.get(:for, [key])
     |> Enum.reduce(%{}, &Map.put(&2, &1, Application.get_all_env(&1)))}
  end

  @impl Kungfuig.Backend
  def transform(%{kungfuig: env}) do
    {:ok, for({k, v} <- env, {_, value} <- v, do: {k, value})}
  end
end

defmodule Kungfuig.Test.Backends.Custom do
  @moduledoc false

  use Kungfuig.Backend, name: :custom

  @impl Kungfuig.Backend
  def get(_meta, _key) do
    {:ok, %{custom: "from custom backend"}}
  end

  @impl Kungfuig.Backend
  def transform(config) do
    {:ok, [custom_value: Map.get(config, :custom, "default")]}
  end
end
