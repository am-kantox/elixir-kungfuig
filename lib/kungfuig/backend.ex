defmodule Kungfuig.Backend do
  @moduledoc """

  The scaffold for the backend watching the external config source.

  ### Example

  ```elixir
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
  ```
  """

  @typedoc "The type for the key withing `Kungfuig`, typically an atom."
  @type key :: term()

  @doc "The key this particular config would be stored under, defaults to module name"
  @callback key :: key()

  @doc "The implementation of the call to remote that retrieves the data"
  @callback get([Kungfuig.option()]) :: {:ok, any()} | {:error, any()}

  @doc "The implementation of the call to remote that retrieves the data under a key specified"
  @callback get([Kungfuig.option()], key()) :: {:ok, any()} | {:error, any()}

  @doc "The transformer that converts the retrieved data to internal representation"
  @callback transform(any()) :: {:ok, any()} | {:error, any()}

  @doc "The implementation of error reporting"
  @callback report(any()) :: :ok

  @optional_callbacks key: 0, transform: 1, report: 1

  @doc false
  defmacro __using__(opts \\ []) do
    quote location: :keep, generated: true, bind_quoted: [opts: opts] do
      @behaviour Kungfuig.Backend

      {key, opts} =
        Keyword.pop_lazy(
          opts,
          :key,
          fn ->
            __MODULE__ |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()
          end
        )

      {report, opts} = Keyword.pop(opts, :report, :none)

      @impl Kungfuig.Backend
      def key, do: unquote(key)

      @impl Kungfuig.Backend
      def transform(any), do: {:ok, any}

      @impl Kungfuig.Backend
      case report do
        :logger ->
          require Logger

          def report(error),
            do:
              Logger.warning(fn ->
                "Failed to retrieve config in #{key()}. Error: #{inspect(error)}."
              end)

        _ ->
          def report(_any), do: :ok
      end

      @impl Kungfuig.Backend
      def get(meta), do: get(meta, unquote(key))

      defoverridable Kungfuig.Backend

      @opts opts
      use Kungfuig, @opts

      @impl Kungfuig
      def update_config(%Kungfuig{__meta__: meta, state: %{} = state}) do
        with {:ok, result} <- get(meta),
             {:ok, result} <- transform(result) do
          Map.put(state, key(), result)
        else
          {:error, error} ->
            if Keyword.get(meta, :report?, true), do: report(error)
            state
        end
      end

      defp smart_validate(nil, options), do: {:ok, options}
      defp smart_validate(Kungfuig.Validators.Void, options), do: {:ok, options}

      defp smart_validate(validator, options) do
        with {:ok, validated} <- validator.validate(options[key()]),
             do: {:ok, %{options | key() => validated}}
      end

      defp report_error(error), do: report(error)
    end
  end

  @doc false
  @spec create(name :: module(), domain :: module(), key :: atom()) :: module()
  def create(name, domain \\ nil, key) do
    with {:module, ^name, _binary, _term} <-
           Module.create(name, content(domain: domain, key: key), Macro.Env.location(__ENV__)),
         do: name
  end

  @doc false
  def content(opts) do
    quote generated: true, location: :keep, bind_quoted: [opts: opts] do
      domain = Keyword.get(opts, :domain, :kungfuig)

      {domain, domain_key} =
        case to_string(domain) do
          "Elixir." <> name ->
            {domain,
             domain |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()}

          shorty ->
            {Module.concat([Kungfuig.Backend, Macro.camelize(shorty)]), shorty}
        end

      @domain domain
      @domain_key domain_key
      @report Keyword.get(opts, :report, :logger)
      @key Keyword.get(opts, :key, :kungfuig)

      use Kungfuig.Backend, key: @domain_key, report: @report

      @impl Kungfuig.Backend
      def get(meta, key), do: @domain.get(meta, key)

      @impl Kungfuig.Backend
      def get(meta), do: get(meta, @key)
    end
  end
end
