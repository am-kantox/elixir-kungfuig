defmodule Kungfuig.Validators.Env do
  @moduledoc false

  use Kungfuig.Validator,
    schema: [env: [type: :any, required: false], system: [type: :any, required: false]]
end

defmodule Kungfuig.Validators.EnvTransform do
  @moduledoc false

  use Kungfuig.Validator, schema: [foo_transform: [type: :atom, required: false]]
end
