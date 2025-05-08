defmodule Kungfuig do
  @moduledoc """
  `Kungfuig` provides a pluggable drop-in support for live configurations.

  This behaviour defines the dynamic config provider. One would barely need to implement
    this behaviour, instead one needs to implement one or more backends (see `Kungfuig.Backend`)
    and then pass them, parametrized if wished, as `workers:` to `start_link/1` as shown below

  ```elixir
    {:ok, pid} =
      Kungfuig.start_link(
        workers: [
          {Kungfuig.Backends.EnvTransform,
           interval: 100,
           validator: Kungfuig.Validators.EnvTransform,
           callback: {self(), {:info, :updated}},
           callback: Kungfuig.Test.CallbackAlert}
        ]
      )
  ```

  By default, `Kungfuig` starts two backends, for the application environment
    (`Application.get_all_env/1`) and for the system environment.

  If one needs to get the updates from the configuration stored somewhere else,
    e. g. json/yaml/ini files, redis, whatever else, they are after introducing
    their own backends (see `Kungfuig.Backend` for the reference and/or
    [Usage](https://hexdocs.pm/kungfuig/readme.html#using) for the example
    using `MySQL`.)

  ### Examples

      Kungfuig.start_link()
      Kungfuig.config()
      #⇒ %{env: %{kungfuig: []}, system: %{}}

      Kungfuig.config(:env)
      #⇒ %{kungfuig: []}

      Application.put_env(:kungfuig, :foo, 42)
      Kungfuig.config(:env)
      #⇒ %{kungfuig: [foo: 42]}

  The configuration gets frequently updated.
  """

  @typedoc "The config map to be updated and exposed through callback"
  @type config :: %{required(atom()) => term()}

  @typedoc """
  The callback to be used for subscibing to config updates.

  Might be an anonymous function, an `{m, f}` tuple accepting a single argument,
  or a process identifier accepting `call`, `cast` or simple message (`:info`.)

  Also, the callback might be an implementation of `Kungfuig.Callback` behaviour.
  """
  @type callback ::
          module()
          | {module(), atom()}
          | (config() -> :ok)
          | {GenServer.name() | pid(), {:call | :cast | :info, atom()}}

  @typedoc "The option that can be passed to `start_link/1` function"
  @type option ::
          {:name, GenServer.name()}
          | {:callback, callback()}
          | {:interval, non_neg_integer()}
          | {:anonymous, boolean()}
          | {:start_options, [GenServer.option()]}
          | {atom(), term()}

  @typedoc "The config that is managed by this behaviour is a simple map"
  @type t :: %{
          __struct__: Kungfuig,
          __meta__: [option()],
          __start_options__: [],
          __previous__: config(),
          state: config()
        }

  defstruct __meta__: [], __previous__: %{}, state: %{}

  @doc false
  @callback start_link(opts :: [option()]) :: GenServer.on_start()

  @doc false
  @callback update_config(state :: t()) :: config()

  @doc false
  @spec __using__(opts :: [option()]) :: Macro.t()
  defmacro __using__(opts) do
    quote location: :keep, generated: true, bind_quoted: [opts: opts] do
      {anonymous, opts} = Keyword.pop(opts, :anonymous, false)

      use GenServer
      @behaviour Kungfuig

      @impl Kungfuig
      def start_link(opts) do
        opts = Keyword.merge(unquote(opts), opts)

        {start_options, opts} = Keyword.pop(opts, :start_options, [])

        opts =
          opts
          |> Keyword.put_new(:name, __MODULE__)
          |> Keyword.put_new(:imminent, false)
          |> Keyword.put_new(:interval, 1_000)
          |> Keyword.put_new(:validator, Kungfuig.Validators.Void)

        behaviour_checker =
          fn module ->
            # if function_exported?(module, :handle_config_update, 1), do: [], else: [module]
            []
          end

        opts
        |> Keyword.get_values(:callback)
        |> Enum.flat_map(fn
          {target, {type, name}} when type in [:call, :cast, :info] and is_atom(name) -> []
          {m, f} when is_atom(m) and is_atom(f) -> []
          f when is_function(f, 1) -> []
          pid when is_pid(pid) -> []
          module when is_atom(module) -> behaviour_checker.(module)
          other -> [other]
        end)
        |> tap(&if &1 != [], do: raise("Expected callable(s), got: " <> inspect(&1)))

        start_options =
          if unquote(anonymous),
            do: Keyword.delete(start_options, :name),
            else: Keyword.put_new(start_options, :name, Keyword.fetch!(opts, :name))

        GenServer.start_link(__MODULE__, %Kungfuig{__meta__: opts}, start_options)
      end

      @impl Kungfuig
      def update_config(%Kungfuig{state: state}), do: state

      defoverridable Kungfuig

      @impl GenServer
      def init(%Kungfuig{__meta__: meta} = state) do
        if meta[:imminent] == true do
          {:noreply, state} = handle_continue(:update, state)
          {:ok, state}
        else
          {:ok, state, {:continue, :update}}
        end
      end

      @impl GenServer
      def handle_info(:update, %Kungfuig{} = state),
        do: {:noreply, state, {:continue, :update}}

      @impl GenServer
      def handle_continue(
            :update,
            %Kungfuig{__meta__: opts, __previous__: previous, state: state} = config
          ) do
        state =
          with new_state <- update_config(config),
               {:ok, new_state} <- smart_validate(opts[:validator], new_state) do
            if previous != new_state,
              do: opts |> Keyword.get_values(:callback) |> send_callback(new_state)

            new_state
          else
            {:error, error} ->
              report_error(error)
              state
          end

        Process.send_after(self(), :update, opts[:interval])
        {:noreply, %Kungfuig{config | __previous__: state, state: state}}
      end

      @impl GenServer
      def handle_call(:state, _from, %Kungfuig{} = state),
        do: {:reply, state, state}

      defp send_callback(nil, _state), do: :ok

      defp send_callback(many, state) when is_list(many),
        do: Enum.each(many, &send_callback(&1, state))

      defp send_callback(pid, state) when is_pid(pid),
        do: send(pid, {:kungfuig_update, state})

      defp send_callback({target, {:info, m}}, state),
        do: send(target, {m, state})

      defp send_callback({target, {type, m}}, state),
        do: apply(GenServer, type, [target, {m, state}])

      defp send_callback({m, f}, state), do: apply(m, f, [state])
      defp send_callback(f, state) when is_function(f, 1), do: f.(state)

      defp send_callback(module, state) when is_atom(module),
        do: module.handle_config_update(state)

      @spec smart_validate(validator :: nil | module(), options :: map() | keyword()) ::
              {:ok, keyword()} | {:error, any()}
      defp smart_validate(nil, options), do: {:ok, options}
      defp smart_validate(Kungfuig.Validators.Void, options), do: {:ok, options}
      defp smart_validate(validator, options), do: validator.validate(options)

      @spec report_error(error :: any()) :: :ok
      defp report_error(_error), do: :ok

      defoverridable report_error: 1, smart_validate: 2
    end
  end

  @doc """
  The function to start the `Kungfuig` manager under a supervision tree with default options
  """
  defdelegate start_link, to: Kungfuig.Supervisor

  @doc """
  The function to start the `Kungfuig` manager under a supervision tree with custom options
  """
  defdelegate start_link(opts), to: Kungfuig.Supervisor

  @doc """
  Retrieves the current config for the key(s) specified
  """
  @spec config(which :: atom() | [atom()], supervisor :: Supervisor.supervisor()) :: Kungfuig.t()
  def config(which \\ :!, supervisor \\ Kungfuig) do
    result =
      supervisor
      |> Supervisor.which_children()
      |> Enum.find(&match?({_, _, :worker, _}, &1))
      |> case do
        {_blender, pid, :worker, _} when is_pid(pid) ->
          GenServer.call(pid, :state)

        other ->
          raise inspect(other, label: "No blender configured")
      end

    case which do
      nil -> result.state
      :! -> result.state
      which when is_atom(which) -> Map.get(result.state, which, %{})
      which when is_list(which) -> Map.take(result.state, which)
    end
  end
end
