defmodule Kungfuig.Backends.Json do
  @moduledoc false
  require Logger

  @key "priv/json"
  use Kungfuig.Backend, key: @key, report: :logger

  @impl Kungfuig.Backend
  def get(_meta, key) do
    with {:ok, files} <- File.ls(key) do
      files
      |> Enum.flat_map(fn file ->
        with {:ok, content} <- File.read(Path.join(key, file)),
             {:ok, content} <- decode(content) do
          [{file, content}]
        else
          {:error, error} ->
            Logger.warning("Error reading config ‹#{file}›: " <> inspect(error))
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
