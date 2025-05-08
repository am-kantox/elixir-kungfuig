defmodule Kungfuig do
  @moduledoc """
  `Kungfuig` provides a pluggable drop-in support for live configurations with change notification capabilities.

  ## Overview

  Kungfuig (pronounced: [ˌkʌŋˈfig]) is a comprehensive configuration management system for Elixir applications
  that provides:

  * Live configuration updates from multiple sources
  * Callback notifications when configurations change
  * Configuration validation
  * Extensible backend system for custom configuration sources
  * Supervisor-managed configuration processes

  This behaviour defines the dynamic config provider. In most cases, you don't need to implement
  this behaviour directly. Instead, implement one or more backends (see `Kungfuig.Backend`)
  and pass them, optionally parametrized, as `workers:` to `start_link/1` as shown below:

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

  By default, `Kungfuig` starts two backends:
  * Application environment backend (`Application.get_all_env/1`) 
  * System environment backend (for environment variables)

  ## Architecture

  Kungfuig operates using a supervisor tree pattern:

  1. A supervisor (`Kungfuig.Supervisor`) manages the configuration process
  2. A manager process (`Kungfuig.Manager`) supervises the backend workers
  3. Backend workers (`Kungfuig.Backend` implementations) poll their respective configuration sources
  4. A blender process (`Kungfuig.Blender`) combines configurations from all backends
  5. Callbacks are triggered when configurations change

  ## Custom Configuration Sources

  If you need to get configuration updates from sources other than the default ones,
  such as JSON/YAML files, Redis, databases, or any external service, you can create
  your own backends by implementing the `Kungfuig.Backend` behaviour.

  See `Kungfuig.Backend` for reference or check the 
  [Usage](https://hexdocs.pm/kungfuig/readme.html#using) section in the README for an example
  using MySQL.

  ## Validation

  Since v0.3.0, Kungfuig supports validation through the `Kungfuig.Validator` behaviour,
  which by default uses `NimbleOptions` for schema validation. Validators can be specified:

  * Per backend (applying only to that backend's configuration)
  * Globally (applying to the entire configuration)

  ## Callbacks

  When a configuration changes, Kungfuig notifies interested parties through callbacks.
  Multiple callback mechanisms are supported, as detailed in the `t:callback/0` type.

  ## Named Instances

  Since v0.4.0, Kungfuig supports multiple named instances, allowing different parts of your
  application to use separate configuration managers.

  ## Examples

  Basic usage:

  ```elixir
  # Start Kungfuig with default options
  Kungfuig.start_link()

  # Get all configuration
  Kungfuig.config()
  #⇒ %{env: %{kungfuig: []}, system: %{}}

  # Get configuration from a specific backend
  Kungfuig.config(:env)
  #⇒ %{kungfuig: []}

  # Update application environment and see the change
  Application.put_env(:kungfuig, :foo, 42)
  Kungfuig.config(:env)
  #⇒ %{kungfuig: [foo: 42]}
  ```

  Using callbacks:

  ```elixir
  # Using a process message as callback
  Kungfuig.start_link(
    workers: [
      {Kungfuig.Backends.Env, callback: {self(), {:info, :config_updated}}}
    ]
  )

  # Using a module that implements Kungfuig.Callback
  defmodule MyApp.ConfigHandler do
    @behaviour Kungfuig.Callback
    
    @impl true
    def handle_config_update(config) do
      IO.puts("Configuration updated: " <> inspect(config))
    end
  end

  Kungfuig.start_link(
    workers: [
      {Kungfuig.Backends.Env, callback: MyApp.ConfigHandler}
    ]
  )
  ```

  Using named instances (since v0.4.0):

  ```elixir
  # Start a named Kungfuig instance
  Kungfuig.start_link(name: MyApp.Config)

  # Query the named instance
  Kungfuig.config(:env, MyApp.Config)
  ```

  Using immediate validation (since v0.4.2):

  ```elixir
  # Start with imminent validation for immediate config processing
  Kungfuig.start_link(
    workers: [
      {Kungfuig.Backends.Env, imminent: true, validator: MyApp.ConfigValidator}
    ]
  )
  ```
  """

  @typedoc """
  The config map to be updated and exposed through callbacks.

  This is a map where the keys are atoms (typically representing backend names) and
  the values are the configuration data from those backends.
  """
  @type config :: %{required(atom()) => term()}

  @typedoc """
  The callback to be used for subscribing to configuration updates.

  Kungfuig supports several callback mechanisms:

  * **Module implementing `Kungfuig.Callback` behaviour**:
    ```elixir
    defmodule MyApp.ConfigHandler do
      @behaviour Kungfuig.Callback
      
      @impl true
      def handle_config_update(config) do
        # Handle configuration update
        :ok
      end
    end
    ```

  * **Process identifier (PID)**: The process will receive a `{:kungfuig_update, config}` message
    ```elixir
    # In a GenServer
    def handle_info({:kungfuig_update, config}, state) do
      # Handle configuration update
      {:noreply, state}
    end
    ```

  * **Module-function tuple**: A tuple `{module, function}` where the function accepts a single 
    argument (the configuration)
    ```elixir
    defmodule MyApp.ConfigHandler do
      def on_config_update(config) do
        # Handle configuration update
      end
    end
    
    # In your Kungfuig setup
    callback: {MyApp.ConfigHandler, :on_config_update}
    ```

  * **Anonymous function**: A function that takes one argument (the configuration)
    ```elixir
    callback: fn config -> 
      # Handle configuration update
      :ok 
    end
    ```

  * **GenServer interaction tuple**: A tuple specifying a GenServer and how to interact with it
    ```elixir
    # Send a cast to a GenServer
    callback: {MyGenServer, {:cast, :config_updated}}
    
    # Inside the GenServer
    def handle_cast({:config_updated, config}, state) do
      # Handle configuration update
      {:noreply, state}
    end
    ```
  """
  # Module implementing Kungfuig.Callback
  @type callback ::
          module()
          # Process that will receive {:kungfuig_update, config}
          | pid()
          # {Module, Function} tuple
          | {module(), atom()}
          # Anonymous function
          | (config() -> :ok)
          # GenServer interaction
          | {GenServer.name() | pid(), {:call | :cast | :info, atom()}}

  @typedoc """
  The options that can be passed to `start_link/1` function.

  Options include:

  * `:name` - The name to register the Kungfuig instance under. Default is `Kungfuig`. 
    @since v0.4.0

  * `:callback` - One or more callbacks to notify when configuration changes. See `t:callback/0`.

  * `:interval` - How frequently to check for configuration updates, in milliseconds. 
    Default is 1000 (1 second).

  * `:imminent` - When `true`, performs configuration validation immediately during initialization,
    rather than as a continuation after init returns. Default is `false`.
    @since v0.4.2

  * `:anonymous` - When `true`, the GenServer is not registered under a name.
    Default is `false`.

  * `:start_options` - Options passed to `GenServer.start_link/3`.

  * `:validator` - A module implementing the `Kungfuig.Validator` behaviour to validate
    the configuration. Default is `Kungfuig.Validators.Void` (no validation).
    @since v0.3.0

  * `:workers` - A list of backend specifications, each either a module name or a 
    `{module, opts}` tuple.
  """
  # The name to register the Kungfuig instance under
  @type option ::
          {:name, GenServer.name()}
          | {:callback, callback()}
          | {:interval, non_neg_integer()}
          | {:imminent, boolean()}
          | {:anonymous, boolean()}
          | {:start_options, GenServer.options()}
          | {:validator, module()}
          | {:workers, [module() | {module(), keyword()}]}

  defstruct __meta__: [], __previous__: %{}, state: %{}

  @doc false
  @callback start_link(opts :: [option()]) :: GenServer.on_start()

  @doc false
  @callback update_config(state :: config()) :: config()

  @doc false
  @spec __using__(opts :: [option()]) :: Macro.t()
  defmacro __using__(opts) do
    quote location: :keep, generated: true, bind_quoted: [opts: opts] do
      {anonymous, opts} = Keyword.pop(opts, :anonymous, false)

      use GenServer
      @behaviour Kungfuig

      @impl Kungfuig
      @doc """
      Starts a `#{inspect(__MODULE__)}` process linked to the current process.
      """
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
      @doc false
      def update_config(%Kungfuig{state: state}), do: state

      defoverridable Kungfuig

      @impl GenServer
      @doc false
      def init(%Kungfuig{__meta__: meta} = state) do
        if meta[:imminent] == true do
          {:noreply, state} = handle_continue(:update, state)
          {:ok, state}
        else
          {:ok, state, {:continue, :update}}
        end
      end

      @impl GenServer
      @doc false
      def handle_info(:update, %Kungfuig{} = state),
        do: {:noreply, state, {:continue, :update}}

      @impl GenServer
      @doc false
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
      @doc false
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
  @spec config(which :: atom() | [atom()], supervisor :: Supervisor.supervisor()) ::
          Kungfuig.config()
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
