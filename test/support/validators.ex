defmodule Kungfuig.Validators.Env do
  @moduledoc false

  use Kungfuig.Validator,
    schema: [env: [type: :any, required: false], system: [type: :any, required: false]]
end

defmodule Kungfuig.Validators.EnvTransform do
  @moduledoc false

  use Kungfuig.Validator,
    schema: [
      env_transform: [type: :keyword_list, keys: [foo_transform: [type: :atom, required: false]]],
      foo_transform: [type: :atom, required: false]
    ]
end

defmodule Kungfuig.Test.Validators.CustomTypes do
  @moduledoc false
  use Kungfuig.Validator,
    schema: [
      immediate_validation: [
        type: :keyword_list,
        keys: [
          string_value: [type: :string, required: false],
          integer_value: [type: :integer, required: false],
          float_value: [type: :float, required: false],
          boolean_value: [type: :boolean, required: false],
          array_value: [type: {:list, :string}, required: false],
          map_value: [type: :map, required: false]
        ]
      ],
      delayed_validation: [
        type: :keyword_list,
        keys: [
          string_value: [type: :string, required: false],
          integer_value: [type: :integer, required: false],
          float_value: [type: :float, required: false],
          boolean_value: [type: :boolean, required: false],
          array_value: [type: {:list, :string}, required: false],
          map_value: [type: :map, required: false]
        ]
      ],
      isolated_instance1: [
        type: :keyword_list,
        keys: [
          config: [
            type: :map,
            keys: [
              string_value: [type: :string, required: false],
              integer_value: [type: :integer, required: false],
              float_value: [type: :float, required: false],
              boolean_value: [type: :boolean, required: false],
              array_value: [type: {:list, :string}, required: false],
              map_value: [type: :map, required: false]
            ]
          ]
        ]
      ],
      isolated_instance2: [
        type: :keyword_list,
        keys: [
          config: [
            type: :map,
            keys: [
              string_value: [type: :string, required: false],
              integer_value: [type: :integer, required: false],
              float_value: [type: :float, required: false],
              boolean_value: [type: :boolean, required: false],
              array_value: [type: {:list, :string}, required: false],
              map_value: [type: :map, required: false]
            ]
          ]
        ]
      ]
    ]
end

defmodule Kungfuig.Test.Validators.Complex do
  @moduledoc false
  use Kungfuig.Validator,
    schema: [
      kf_complex: [
        type: :keyword_list,
        keys: [
          test_config: [
            type: :map,
            keys: [
              nested: [
                type: :map,
                keys: [
                  key1: [type: :string, required: true],
                  key2: [type: :integer, required: true]
                ],
                required: true
              ],
              optional_value: [type: :string, required: false],
              enum_value: [type: {:in, [:one, :two, :three]}, required: true]
            ]
          ]
        ]
      ]
    ]
end

defmodule Kungfuig.Test.Validators.ErrorReporting do
  @moduledoc false
  use Kungfuig.Validator,
    schema: [
      kf_errors: [
        type: :keyword_list,
        required: false,
        keys: [
          test_config: [
            required: false,
            type: :map,
            keys: [
              must_be_positive: [
                type: {:custom, __MODULE__, :custom_validation, []},
                required: true
              ]
            ]
          ]
        ]
      ]
    ]

  def custom_validation(value),
    do: if(value > 0, do: {:ok, value}, else: {:error, "must be positive"})
end
