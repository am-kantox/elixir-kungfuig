defmodule Kungfuig.Supervisor do
  @moduledoc false

  use Supervisor

  alias Kungfuig.{Backends, Blender, Manager}

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, Kungfuig)
    Supervisor.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  @impl true
  def init(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    {callbacks, opts} = Keyword.split(opts, [:callback])
    {blender, opts} = Keyword.pop(opts, :blender, Blender)

    blender_name = Module.concat([name, "Blender"])

    {blender, blender_opts} =
      case blender do
        module when is_atom(module) -> {module, [name: blender_name]}
        {module, opts} -> {module, Keyword.put_new(opts, :name, blender_name)}
      end

    blender_name = Keyword.fetch!(blender_opts, :name)

    {workers, opts} =
      Keyword.pop_lazy(
        opts,
        :workers,
        fn -> Application.get_env(:kungfuig, :backends, [Backends.Env, Backends.System]) end
      )

    callbacks = [{:callback, {blender_name, {:call, :updated}}} | callbacks]

    workers =
      Enum.map(workers, fn
        module when is_atom(module) -> {module, callbacks}
        {module, opts} -> {module, callbacks ++ opts}
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
end
