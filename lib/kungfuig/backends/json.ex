defmodule Kungfuig.Backends.Json do
  @moduledoc false
  require Logger

  use Kungfuig.Backend, report: :logger

  alias Kungfuig.Parser

  @dir "priv"

  defmacro __using__(opts \\ []) do
    Kungfuig.Backend.content(opts)
  end

  @impl Kungfuig.Backend
  def get(meta, key) do
    key = Path.join(Keyword.get(meta, :for, @dir), to_string(key))

    case File.ls(key) do
      {:ok, files} ->
        files
        |> Enum.flat_map(fn file ->
          path = Path.join(key, file)

          with {:ok, content} <- File.read(path),
               {:ok, content} <- decode(content) do
            [{file, content}]
          else
            error ->
              Logger.warning("Error reading config ‹#{path}›: " <> inspect(error))
              []
          end
        end)
        |> then(&{:ok, &1 |> Map.new() |> parse()})

      error ->
        Logger.warning("Error reading config ‹#{key}›: " <> inspect(error))
        {:error, error}
    end
  end

  defp parse(%{"type" => _type} = map), do: Parser.value(map)
  defp parse(values) when is_list(values), do: Enum.map(values, &parse/1)
  defp parse(%{} = values), do: Map.new(values, fn {key, value} -> {key, parse(value)} end)
  defp parse(value), do: value

  cond do
    match?({:module, _}, Code.ensure_compiled(:json)) ->
      def decode(binary) do
        {:ok, :json.decode(binary)}
      rescue
        e in ErlangError -> {:error, e}
      end

    match?({:module, _}, Code.ensure_compiled(Jason)) ->
      defdelegate decode(binary), to: Jason

    match?({:module, _}, Code.ensure_compiled(Poison)) ->
      defdelegate decode(binary), to: Poison

    true ->
      def decode(binary), do: {:error, :no_json_parser}
  end
end
