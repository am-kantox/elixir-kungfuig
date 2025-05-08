# ![Kungfuig](https://raw.githubusercontent.com/kantox/kungfuig/master/stuff/kungfuig-48x48.png) Kungfuig    [![Kantox ❤ OSS](https://img.shields.io/badge/❤-kantox_oss-informational.svg)](https://kantox.com/)  ![Test](https://github.com/kantox/kungfuig/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/kantox/kungfuig/workflows/Dialyzer/badge.svg)

## Intro

Live config supporting many different backends.

**Kungfuig** (_pronounced:_ [ˌkʌŋˈfig]) provides an easy way to plug
live configuration into everything.

It provides backends for `env` and `system` and supports custom backends. Configurations are periodically updated, and changes can trigger callback notifications to relevant application components.

## Installation

```elixir
def deps do
  [
    {:kungfuig, "~> 1.0"}
  ]
end
```

## Architecture

Kungfuig is designed with a robust architecture that provides flexibility and reliability:

![Kungfuig Architecture](https://raw.githubusercontent.com/kantox/kungfuig/master/stuff/kungfuig.drawio.png)

The architecture consists of several key components:

1. **Supervisor** (`Kungfuig.Supervisor`): Manages the configuration process tree
2. **Manager** (`Kungfuig.Manager`): Supervises the backend workers
3. **Backend Workers** (`Kungfuig.Backend` implementations): Poll configuration sources
4. **Blender** (`Kungfuig.Blender`): Combines configurations from all backends
5. **Callbacks**: Notify application components when configurations change
6. **Validators**: Ensure configuration values match expected schemas

This architecture provides several benefits:
- Fault tolerance through supervisor patterns
- Separation of concerns between configuration sources
- Unified configuration access for your application
- Pluggable backends for custom configuration sources

## Using

### Basic Usage

**Kungfuig** is the easy way to read the external configuration from sources that are not controlled by the application using it, such as _Redis_, or _Database_.

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

### Custom Backends

Here is an example of a backend implementation for reading configuration from an external MySQL database:

```elixir
defmodule MyApp.Kungfuig.MySQL do
  @moduledoc false

  use Kungfuig.Backend, interval: 300_000 # 5 minutes

  @impl Kungfuig.Backend
  def get(_meta) do
    with {:ok, host} <- System.fetch_env("MYSQL_HOST"),
         {:ok, db} <- System.fetch_env("MYSQL_DB"),
         {:ok, user} <- System.fetch_env("MYSQL_USER"),
         {:ok, pass} <- System.fetch_env("MYSQL_PASS"),
         {:ok, pid} when is_pid(pid) <-
           MyXQL.start_link(hostname: host, database: db, username: user, password: pass),
         result <- MyXQL.query!(pid, "SELECT * FROM some_table") do
      GenServer.stop(pid)

      result =
        result.rows
        |> Flow.from_enumerable()
        |> Flow.map(fn [_, field1, field2, _, _] -> {field1, field2} end)
        |> Flow.partition(key: &elem(&1, 0))
        |> Flow.reduce(fn -> %{} end, fn {field1, field2}, acc ->
          Map.update(
            acc,
            String.to_existing_atom(field1),
            [field2],
            &[field2 | &1]
          )
        end)

      Logger.info("Loaded #{Enum.count(result)} values from " <> host)

      {:ok, result}
    else
      :error ->
        Logger.warn("Skipped reconfig, one of MYSQL_{HOST,DB,USER,PASS} is missing")
        :ok

      error ->
        Logger.error("Reconfiguring failed. Error: " <> inspect(error))
        {:error, error}
    end
  end
end
```

### Callback Patterns

Kungfuig supports multiple callback mechanisms to notify your application when configuration changes:

#### Process Message Callback

```elixir
# Using a PID - the process will receive a {:kungfuig_update, config} message
defmodule MyApp.ConfigConsumer do
  use GenServer
  
  def start_link(_), do: GenServer.start_link(__MODULE__, nil)
  
  def init(_), do: {:ok, %{}}

  # Handle configuration updates
  def handle_info({:kungfuig_update, config}, state) do
    IO.puts("Configuration updated: #{inspect(config)}")
    {:noreply, state}
  end
end

# In your application startup
{:ok, pid} = MyApp.ConfigConsumer.start_link([])
Kungfuig.start_link(workers: [{Kungfuig.Backends.Env, callback: pid}])
```

#### Callback Behaviour Implementation

```elixir
defmodule MyApp.ConfigHandler do
  @behaviour Kungfuig.Callback
  
  @impl true
  def handle_config_update(config) do
    IO.puts("Configuration updated: #{inspect(config)}")
    :ok
  end
end

# In your application startup
Kungfuig.start_link(workers: [{Kungfuig.Backends.Env, callback: MyApp.ConfigHandler}])
```

#### GenServer Interaction Callbacks

```elixir
# Using a GenServer cast
defmodule MyApp.ConfigManager do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  
  def init(_), do: {:ok, %{}}

  def handle_cast({:config_updated, config}, state) do
    # Process configuration update
    {:noreply, Map.put(state, :config, config)}
  end
end

# In your application startup
MyApp.ConfigManager.start_link([])
Kungfuig.start_link(
  workers: [
    {Kungfuig.Backends.Env, callback: {MyApp.ConfigManager, {:cast, :config_updated}}}
  ]
)
```

#### Function Callback

```elixir
# Using an anonymous function
callback_fn = fn config ->
  IO.puts("Config updated: #{inspect(config)}")
  :ok
end

Kungfuig.start_link(workers: [{Kungfuig.Backends.Env, callback: callback_fn}])
```

### Validation System

Since v0.3.0, Kungfuig supports configuration validation through the `Kungfuig.Validator` behavior, which by default uses `NimbleOptions` for schema validation.

#### Creating a Custom Validator

```elixir
defmodule MyApp.ConfigValidator do
  use Kungfuig.Validator, schema: [
    database: [
      type: :string,
      required: true,
      doc: "The database name"
    ],
    hostname: [
      type: :string,
      required: true,
      doc: "The database hostname"
    ],
    port: [
      type: :integer,
      default: 5432,
      doc: "The database port"
    ],
    ssl: [
      type: :boolean,
      default: false,
      doc: "Whether to use SSL"
    ]
  ]
end
```

#### Using the Validator

You can apply validators at two levels:

1. **Per backend** - to validate only this backend's configuration:

```elixir
Kungfuig.start_link(
  workers: [
    {MyApp.Kungfuig.DatabaseBackend, validator: MyApp.ConfigValidator}
  ]
)
```

2. **Global validator** - to validate the entire configuration:

```elixir
Kungfuig.start_link(
  validator: MyApp.GlobalConfigValidator,
  workers: [
    MyApp.Kungfuig.DatabaseBackend,
    MyApp.Kungfuig.RedisBackend
  ]
)
```

### Named Instances

Since v0.4.0, Kungfuig supports multiple named instances, allowing different parts of your application to use separate configuration managers.

```elixir
# Start a Kungfuig instance for database configuration
Kungfuig.start_link(
  name: MyApp.DBConfig,
  workers: [
    {MyApp.Kungfuig.DatabaseBackend, interval: 60_000}
  ]
)

# Start another Kungfuig instance for API configuration
Kungfuig.start_link(
  name: MyApp.APIConfig,
  workers: [
    {MyApp.Kungfuig.APIBackend, interval: 30_000}
  ]
)

# Query the configurations separately
db_config = Kungfuig.config(:database, MyApp.DBConfig)
api_config = Kungfuig.config(:api, MyApp.APIConfig)
```

### Immediate Configuration Processing

Since v0.4.2, Kungfuig allows immediate configuration validation using the `imminent: true` option:

```elixir
Kungfuig.start_link(
  workers: [
    {Kungfuig.Backends.Env, imminent: true}
  ]
)
```

This option ensures that the configuration is validated and processed during the init phase, rather than as a continuation after init returns. This is useful when your application requires the configuration to be available immediately upon startup.

## Testing

Simply implement a stub returning an expected config and you are all set.

```elixir
defmodule MyApp.Kungfuig.Stub do
  @moduledoc false

  use Kungfuig.Backend

  @impl Kungfuig.Backend
  def get(_meta), do: %{foo: :bar, baz: [42]}
end
```

## Comparison with Alternatives

Kungfuig offers several advantages compared to other configuration management solutions:

### vs. Application Environment

The standard Elixir Application environment is static after startup unless manually changed:

- **Kungfuig**: Automatically polls for changes at configurable intervals
- **App env**: Requires manual calls to `Application.put_env/3` to update

### vs. Config Providers

Elixir's built-in config providers run only once at application start:

- **Kungfuig**: Continually monitors for changes while the application is running
- **Config providers**: Only run during application startup

### vs. Distillery Config Providers

While Distillery's Config Providers can load configuration on application start:

- **Kungfuig**: Lets you define custom backends for any data source
- **Distillery**: Focused on files and environment variables
- **Kungfuig**: Supports multiple callback types for change notifications
- **Distillery**: Doesn't have built-in change notification

### vs. etcd/Consul/ZooKeeper clients

While these external services provide great configuration management:

- **Kungfuig**: Works with many different backends, not tied to a specific service
- **External services**: Require running and maintaining additional infrastructure
- **Kungfuig**: Simple supervision tree model familiar to Elixir developers
- **External services**: More complex client libraries and connection management

## Changelog

- **`1.0.0`** — modern Elixir v1.16
- **`0.4.4`** — fix a bug with hardcoded names (`Supervisor` and `Blender`)
- **`0.4.2`** — allow `imminent: true` option to `Kungfuig.Backend`
- **`0.4.0`** — allow named `Kungfuig` instances (thanks @vbroskas)
- **`0.3.0`** — allow validation through `NimbleOptions` (per backend and global)
- **`0.2.0`** — scaffold for backends + several callbacks (and the automatic one for `Blender`)

## [Documentation](https://hexdocs.pm/kungfuig)
