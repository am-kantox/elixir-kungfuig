defmodule Kungfuig.Backends.Json do
  @moduledoc false
  require Logger

  use Kungfuig.Backend, report: :logger

  @dir "priv"

  defmacro __using__(opts \\ []) do
    Kungfuig.Backend.content(opts)
  end

  @impl Kungfuig.Backend
  def get(meta, key) do
    key = Path.join(Keyword.get(meta, :for, @dir), to_string(key))

    with {:ok, files} <- File.ls(key) do
      files
      |> Enum.flat_map(fn file ->
        path = Path.join(key, file)

        with {:ok, content} <- File.read(path),
             {:ok, content} <- decode(content) do
          [{file, content}]
        else
          {:error, error} ->
            Logger.warning("Error reading config ‹#{path}›: " <> inspect(error))
            []
        end
      end)
      |> then(&{:ok, Map.new(&1)})
    end
  end

  cond do
    Code.ensure_loaded?(:json) ->
      def decode(binary) do
        {:ok, :json.decode(binary)}
      rescue
        e in ErlangError -> {:error, e}
      end

    Code.ensure_loaded?(Jason) ->
      defdelegate decode(binary), to: Jason

    Code.ensure_loaded?(Poison) ->
      defdelegate decode(binary), to: Poison

    true ->
      def decode(binary), do: {:error, :no_json_parser}
  end
end
