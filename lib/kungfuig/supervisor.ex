defmodule Kungfuig.Supervisor do
  @moduledoc false

  use Supervisor

  alias Kungfuig.{Backends, Blender, Manager}

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, Kungfuig)

    updater = fn
      {:backend, domain} ->
        module = Module.concat([domain, name])

        if Code.ensure_loaded?(module) do
          module
        else
          key = name |> Macro.underscore() |> String.to_atom()
          Kungfuig.Backend.create(module, domain, key)
        end

      constructor when is_function(constructor, 1) ->
        constructor.(name)

      other ->
        other
    end

    opts =
      opts
      |> Keyword.put_new(:workers, standard_workers())
      |> Keyword.update!(:workers, &Enum.map(&1, updater))

    Supervisor.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  @impl true
  def init(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    {callbacks, opts} = Keyword.split(opts, [:callback])
    {blender, opts} = Keyword.pop(opts, :blender, Blender)
    {start_options, opts} = Keyword.pop(opts, :start_options, [])
    {validator, opts} = Keyword.pop(opts, :validator, Kungfuig.Validators.Void)

    blender_name = Module.concat([name, "Blender"])

    {blender, blender_opts} =
      case blender do
        module when is_atom(module) ->
          {module, [start_options: start_options, name: blender_name]}

        {module, opts} ->
          opts =
            opts
            |> Keyword.put_new(:name, blender_name)
            |> Keyword.update(:start_options, start_options, &Keyword.merge(start_options, &1))

          {module, opts}
      end

    blender_name = Keyword.fetch!(blender_opts, :name)

    {workers, opts} = Keyword.pop!(opts, :workers)

    callbacks = [{:callback, {blender_name, {:call, :updated}}} | callbacks]

    workers =
      Enum.map(workers, fn
        module when is_atom(module) -> {module, [{:validator, validator} | callbacks]}
        {module, opts} -> {module, callbacks ++ Keyword.put_new(opts, :validator, validator)}
      end)

    manager_name = Module.concat([blender_name, "Manager"])

    {:ok, pid} =
      Task.start_link(fn ->
        receive do
          :ready -> Enum.each(workers, &DynamicSupervisor.start_child(manager_name, &1))
        end
      end)

    children = [
      {blender, blender_opts},
      {Manager, start_options: [name: manager_name], post_mortem: pid}
    ]

    Supervisor.init(children, Keyword.put_new(opts, :strategy, :one_for_one))
  end

  defp standard_workers do
    Application.get_env(:kungfuig, :backends, [
      {:backend, Backends.Env},
      {:backend, Backends.System}
    ])
  end
end
