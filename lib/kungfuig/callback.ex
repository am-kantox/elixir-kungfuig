defmodule Kungfuig.Callback do
  @moduledoc """
  The behaviour defining the dynamic config provider’s callback.

  `Kungfuig ` accepts callbacks in several forms, see `t:Kungfuig.callback/0`.
  """

  @doc """
    The callback to be used for subscribing to config updates.
  """
  @callback handle_config_update(Kungfuig.config()) :: :ok
end
