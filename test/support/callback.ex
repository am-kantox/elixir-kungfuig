defmodule Kungfuig.Test.CallbackAlert do
  @moduledoc false
  @behaviour Kungfuig.Callback

  @impl Kungfuig.Callback
  def handle_config_update(config) do
    require Logger
    Logger.alert("Config updated: " <> inspect(config))
    :ok
  end
end

defmodule Kungfuig.Test.CallbackError do
  @moduledoc false
  @behaviour Kungfuig.Callback

  @impl Kungfuig.Callback
  def handle_config_update(config) do
    require Logger
    Logger.error("Config updated: " <> inspect(config))
    :ok
  end
end
