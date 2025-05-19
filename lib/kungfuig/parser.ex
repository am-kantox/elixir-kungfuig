defmodule Kungfuig.Parser do
  @moduledoc """
  The parser for the value read from a config.

  It is designed to simplify reading and instantiating values read from json
    to elixir entities.

  Supported types:

  - `{"type": "atom", "value": "foo"}` — the atom `:foo`
  - `{"type": "existing_atom", "value": "foo"}` — the existing atom `:foo`
  - `{"type": "function", "module": module, "function": function, "arity": arity}` — the function to instantiate
  - `{"type": "existing_function", "module": module, "function": function, "arity": arity}` — the existing function to instantiate
  - `{"type": "tuple", "value": ["foo", 42]}` — the tuple `{"foo", 42}`
  """

  @doc """
  Retrieves and instantiates the actial value out of json object 
  """
  def value(%{"type" => "atom", "value" => value}), do: String.to_atom(value)
  def value(%{"type" => "existing_atom", "value" => value}), do: String.to_existing_atom(value)

  def value(%{"type" => "tuple", "value" => value}) when is_list(value),
    do: value |> Enum.map(&value/1) |> List.to_tuple()

  def value(%{"type" => "function", "module" => module, "function" => function, "arity" => arity}) do
    Function.capture(
      String.to_atom(fix_module(module)),
      String.to_atom(function),
      arity
    )
  end

  def value(%{
        "type" => "existing_function",
        "module" => module,
        "function" => function,
        "arity" => arity
      }) do
    Function.capture(
      String.to_existing_atom(fix_module(module)),
      String.to_existing_atom(function),
      arity
    )
  rescue
    e ->
      require Logger
      Logger.error("Error parsing value: " <> inspect(e))
      nil
  end

  def value(ordinar), do: ordinar

  defp fix_module(module) do
    with grapheme <- String.first(module),
         true <- String.capitalize(grapheme) == grapheme,
         do: "Elixir." <> module,
         else: (false -> module)
  end
end
