defmodule Kungfuig.Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  doctest Kungfuig

  test "custom target" do
    {:ok, pid} =
      Kungfuig.start_link(
        name: KF1,
        blender:
          {Kungfuig.Blender,
           name: Server1Blender, interval: 100, validator: Kungfuig.Validators.Env},
        callback: {self(), {:info, :updated}}
      )

    assert_receive {:updated, %{env: %{kf1: []}}}, 1_100

    Application.put_env(:kf1, :foo, 42)

    assert_receive {:updated, %{env: %{kf1: [foo: 42]}}}, 1_100

    System.put_env("KF1_FOO", "42")
    assert_receive {:updated, %{system: %{"KF1_FOO" => "42"}}}, 1_100

    assert Kungfuig.config(:!, KF1) == %{
             env: %{kf1: [foo: 42]},
             system: %{"KF1_FOO" => "42"}
           }

    Application.delete_env(:kf1, :foo)
    System.delete_env("KF1_FOO")
    Supervisor.stop(pid)
  end

  test "transform/1" do
    {:ok, pid} =
      Kungfuig.start_link(
        workers: [
          {Kungfuig.Backends.EnvTransform,
           interval: 100,
           validator: Kungfuig.Validators.EnvTransform,
           callback: {self(), {:info, :updated}},
           callback: Kungfuig.Test.CallbackAlert}
        ]
      )

    assert_receive {:updated, %{kungfuig: []}}, 200

    Application.put_env(:kungfuig, :foo_transform, %{bar: :baz})
    assert_receive {:updated, %{kungfuig: [foo_transform: :baz]}}, 1_020
    assert Kungfuig.config() == %{kungfuig: [foo_transform: :baz]}

    assert capture_log([level: :info], fn ->
             Application.put_env(:kungfuig, :foo_transform, %{bar: 42})
             refute_receive({:updated, %{kungfuig: [foo_transform: 42]}}, 120)
           end) =~ "atom, got: 42"

    assert Kungfuig.config() == %{kungfuig: [foo_transform: :baz]}

    Application.delete_env(:kungfuig, :foo_transform)
    Supervisor.stop(pid)
  end

  test "custom target with via registered name" do
    {:ok, pid} =
      Kungfuig.start_link(
        name: KF2,
        blender: {Kungfuig.Blender, interval: 100, validator: Kungfuig.Validators.Env},
        callback: {self(), {:info, :updated}}
      )

    assert_receive {:updated, %{env: %{kf2: []}}}, 1_100

    Application.put_env(:kf2, :bar, 24)

    assert_receive {:updated, %{env: %{kf2: [bar: 24]}}}, 1_100

    System.put_env("KF2_BAR", "24")
    assert_receive {:updated, %{system: %{"KF2_BAR" => "24"}}}, 1_100

    assert Kungfuig.config(nil, KF2) == %{
             env: %{kf2: [bar: 24]},
             system: %{"KF2_BAR" => "24"}
           }

    Application.delete_env(:kf2, :bar)
    System.delete_env("KF2_BAR")
    Supervisor.stop(pid)
  end

  describe "validator functionality" do
    test "validates custom types correctly" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: KFValidTypes,
          validator: Kungfuig.Test.Validators.CustomTypes,
          callback: self()
        )

      valid_config = %{
        string_value: "test",
        integer_value: 42,
        float_value: 3.14,
        boolean_value: true,
        array_value: ["one", "two"],
        map_value: %{key: "value"}
      }

      Application.put_env(:kungfuig, :test_config, valid_config)
      assert_receive {:kungfuig_update, _config}, 1_100

      # Test invalid types
      invalid_config = %{
        # should be string
        string_value: 123,
        # should be integer
        integer_value: "42",
        # should be float
        float_value: "3.14",
        # should be boolean
        boolean_value: "true",
        # should be list of strings
        array_value: [1, 2],
        # should be map
        map_value: "not_a_map"
      }

      Application.put_env(:kungfuig, :test_config, invalid_config)
      refute_receive {:kungfuig_update, _config}, 1_100

      Application.delete_env(:kungfuig, :test_config)
      Supervisor.stop(pid)
    end

    test "handles complex validation schemas" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: KFComplex,
          validator: Kungfuig.Test.Validators.Complex,
          callback: self()
        )

      assert_receive {:kungfuig_update, _config}, 1_100

      valid_config = %{
        nested: %{
          key1: "value",
          key2: 42
        },
        optional_value: "optional",
        enum_value: :one
      }

      Application.put_env(:kf_complex, :test_config, valid_config)

      assert_receive {:kungfuig_update,
                      %{
                        env: %{
                          kf_complex: [
                            test_config: %{
                              nested: %{key1: "value", key2: 42},
                              optional_value: "optional",
                              enum_value: :one
                            }
                          ]
                        }
                      }},
                     1_100

      # Test with missing optional value
      valid_config_2 = %{
        nested: %{
          key1: "value",
          key2: 42
        },
        enum_value: :two
      }

      Application.put_env(:kf_complex, :test_config, valid_config_2)
      assert_receive {:kungfuig_update, _config}, 1_100

      # Test invalid enum value
      invalid_config = %{
        nested: %{
          key1: "value",
          key2: 42
        },
        enum_value: :invalid
      }

      Application.put_env(:kf_complex, :test_config, invalid_config)
      refute_receive {:kungfuig_update, _config}, 1_100

      Application.delete_env(:kf_complex, :test_config)
      Supervisor.stop(pid)
    end

    test "reports validation errors correctly" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: KFErrors,
          validator: Kungfuig.Test.Validators.ErrorReporting,
          callback: self()
        )

      assert_receive {:kungfuig_update, %{env: %{}}}, 1_100

      valid_config = %{
        must_be_positive: 42
      }

      Application.put_env(:kf_errors, :test_config, valid_config)

      assert_receive {:kungfuig_update,
                      %{env: %{kf_errors: [test_config: %{must_be_positive: 42}]}}},
                     1_100

      # Test custom validation error
      invalid_config = %{
        must_be_positive: -1
      }

      log =
        capture_log(fn ->
          Application.put_env(:kf_errors, :test_config, invalid_config)
          refute_receive {:kungfuig_update, %{env: %{}}}, 1_100
        end)

      assert log =~ "must be positive"

      Application.delete_env(:kf_errors, :test_config)
      Supervisor.stop(pid)
    end

    test "smart_validate handles different validator types" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: KFSmartValidate,
          validator: Kungfuig.Validators.Void,
          callback: self()
        )

      # Test with void validator (should pass everything)
      Application.put_env(:kungfuig, :test_config, %{any: "value"})
      assert_receive {:kungfuig_update, _config}, 1_100

      # Test with nil validator (should pass everything)
      {:ok, pid2} =
        Kungfuig.start_link(
          name: KFSmartValidate2,
          validator: nil,
          callback: self()
        )

      Application.put_env(:kungfuig, :test_config2, %{any: "value"})
      assert_receive {:kungfuig_update, _config}, 1_100

      Application.delete_env(:kungfuig, :test_config)
      Application.delete_env(:kungfuig, :test_config2)
      Supervisor.stop(pid)
      Supervisor.stop(pid2)
    end
  end

  describe "callback mechanisms" do
    test "module implementing Kungfuig.Callback behaviour" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: KFCallbackModule,
          callback: Kungfuig.Test.CallbackAlert
        )

      log =
        capture_log(fn ->
          Application.put_env(:kf_callback_module, :test_config, %{value: 42})
          Process.sleep(1_100)
        end)

      assert log =~ "Config updated:"
      assert log =~ "value: 42"

      Application.delete_env(:kf_callback_module, :test_config)
      Supervisor.stop(pid)
    end

    test "process message callbacks" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: KFCallbackProcess,
          callback: self()
        )

      Application.put_env(:kf_callback_process, :test_config, %{value: 42})

      assert_receive {:kungfuig_update,
                      %{env: %{kf_callback_process: [test_config: %{value: 42}]}}},
                     1_100

      Application.delete_env(:kf_callback_process, :test_config)
      Supervisor.stop(pid)
    end

    test "module-function tuple callbacks" do
      Process.register(self(), :test_mfa_pid)

      defmodule TestCallback do
        def on_config_update(config) do
          send(:test_mfa_pid, {:config_updated, config})
        end
      end

      {:ok, pid} =
        Kungfuig.start_link(
          name: KFCallbackMF,
          callback: {TestCallback, :on_config_update}
        )

      Application.put_env(:kf_callback_mf, :test_config, %{value: 42})

      assert_receive {:config_updated, %{env: %{kf_callback_mf: [test_config: %{value: 42}]}}},
                     1_100

      Application.delete_env(:kf_callback_mf, :test_config)
      Supervisor.stop(pid)
    end

    test "anonymous function callbacks" do
      test_pid = self()

      {:ok, pid} =
        Kungfuig.start_link(
          name: KFCallbackAnon,
          callback: fn config -> send(test_pid, {:anon_callback, config}) end
        )

      Application.put_env(:kf_callback_anon, :test_config, %{value: 42})

      assert_receive {:anon_callback, %{env: %{kf_callback_anon: [test_config: %{value: 42}]}}},
                     1_100

      Application.delete_env(:kf_callback_anon, :test_config)
      Supervisor.stop(pid)
    end

    test "GenServer interaction callbacks" do
      defmodule TestServer do
        use GenServer

        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        def init(opts), do: {:ok, opts}

        def handle_call({:config_updated, config}, _from, state) do
          send(state.test_pid, {:call_received, config})
          {:reply, {:ok, config}, state}
        end

        def handle_cast({:config_updated, config}, state) do
          send(state.test_pid, {:cast_received, config})
          {:noreply, state}
        end

        def handle_info({:config_updated, config}, state) do
          send(state.test_pid, {:info_received, config})
          {:noreply, state}
        end
      end

      {:ok, server} = TestServer.start_link(%{test_pid: self()})

      # Test call callback
      {:ok, pid} =
        Kungfuig.start_link(
          callback: {TestServer, {:call, :config_updated}},
          callback: {TestServer, {:cast, :config_updated}},
          callback: {TestServer, {:info, :config_updated}}
        )

      Application.put_env(:kungfuig, :test_config, %{value: 42})
      assert_receive {:call_received, %{env: %{kungfuig: [test_config: %{value: 42}]}}}, 1_100

      Application.put_env(:kungfuig, :test_config, %{value: 43})
      assert_receive {:cast_received, %{env: %{kungfuig: [test_config: %{value: 43}]}}}, 1_100

      Application.put_env(:kungfuig, :test_config, %{value: 44})
      assert_receive {:info_received, %{env: %{kungfuig: [test_config: %{value: 44}]}}}, 1_100

      Application.delete_env(:kungfuig, :test_config)
      Supervisor.stop(pid)
      GenServer.stop(server)
    end

    test "multiple callbacks configuration" do
      Process.register(self(), :test_multiple_callbacks_pid)

      defmodule MultiCallback do
        def on_update(config) do
          send(:test_multiple_callbacks_pid, {:multi_callback, config})
        end
      end

      {:ok, pid} =
        Kungfuig.start_link(
          name: KFMultiCallback,
          callback: self(),
          callback: {MultiCallback, :on_update},
          callback: fn config -> send(:test_multiple_callbacks_pid, {:anon_multi, config}) end
        )

      Application.put_env(:kf_multi_callback, :test_config, %{value: 42})

      # All callbacks should receive the update
      assert_receive {:kungfuig_update,
                      %{env: %{kf_multi_callback: [test_config: %{value: 42}]}}},
                     1_100

      assert_receive {:multi_callback, %{env: %{kf_multi_callback: [test_config: %{value: 42}]}}},
                     1_100

      assert_receive {:anon_multi, %{env: %{kf_multi_callback: [test_config: %{value: 42}]}}},
                     1_100

      Application.delete_env(:kf_multi_callback, :test_config)
      Supervisor.stop(pid)
    end

    test "callback error handling" do
      test_pid = self()

      defmodule ErrorCallback do
        def on_update(_config) do
          raise "Callback error"
        end
      end

      {:ok, pid} =
        Kungfuig.start_link(
          name: KFCallbackError,
          imminent: false,
          callback: {ErrorCallback, :on_update},
          callback: fn config -> send(test_pid, {:still_working, config}) end
        )

      log =
        capture_log(fn ->
          Application.put_env(:kf_callback_error, :test_config, %{value: 42})
          # The second callback should still work despite the first one failing
          assert_receive {:still_working,
                          %{env: %{kf_callback_error: [test_config: %{value: 42}]}}},
                         1_100
        end)

      assert log =~ "Callback error"

      Application.delete_env(:kf_callback_error, :test_config)
      Supervisor.stop(pid)
    end
  end

  describe "named instances" do
    test "multiple named instances run simultaneously" do
      {:ok, pid1} =
        Kungfuig.start_link(
          name: Instance1,
          callback: self()
        )

      {:ok, pid2} =
        Kungfuig.start_link(
          name: Instance2,
          callback: self()
        )

      # Set different configs for different instances
      Application.put_env(:instance1, :config1, %{value: "first"})
      Application.put_env(:instance2, :config2, %{value: "second"})

      # Verify each instance gets its own updates
      assert_receive {:kungfuig_update, %{env: %{instance1: [_] = config1}}}, 1_100
      assert_receive {:kungfuig_update, %{env: %{instance2: [_] = config2}}}, 1_100

      # Verify configs are isolated
      assert get_in(config1, [:config1]) == %{value: "first"}
      assert get_in(config2, [:config2]) == %{value: "second"}

      # Clean up
      Application.delete_env(:instance1, :config1)
      Application.delete_env(:instance1, :config2)
      Supervisor.stop(pid1)
      Supervisor.stop(pid2)
    end

    test "anonymous instance configuration" do
      {:ok, pid} =
        Kungfuig.start_link(
          anonymous: true,
          callback: self()
        )

      # The instance should still work without a name
      Application.put_env(:kungfuig, :anon_config, %{value: "test"})
      assert_receive {:kungfuig_update, %{env: %{kungfuig: [_ | _]}} = config}, 1_100
      assert get_in(config, [:env, :kungfuig, :anon_config, :value]) == "test"

      Application.delete_env(:kungfuig, :anon_config)
      Supervisor.stop(pid)
    end

    test "named instance config retrieval" do
      {:ok, pid1} =
        Kungfuig.start_link(
          name: ConfigInstance1,
          callback: self()
        )

      {:ok, pid2} =
        Kungfuig.start_link(
          name: ConfigInstance2,
          callback: self()
        )

      # Set different configurations
      Application.put_env(:config_instance1, :test, %{value: "first"})
      Application.put_env(:config_instance2, :test, %{value: "second"})

      # Wait for updates to propagate
      Process.sleep(1_100)

      # Test config retrieval for specific instances
      config1 = Kungfuig.config(:env, ConfigInstance1)
      config2 = Kungfuig.config(:env, ConfigInstance2)

      assert config1[:config_instance1][:test][:value] == "first"
      assert config2[:config_instance2][:test][:value] == "second"

      # Clean up
      Application.delete_env(:config_instance1, :test)
      Application.delete_env(:config_instance2, :test)
      Supervisor.stop(pid1)
      Supervisor.stop(pid2)
    end

    test "instance isolation" do
      {:ok, pid1} =
        Kungfuig.start_link(
          name: IsolatedInstance1,
          callback: self(),
          validator: Kungfuig.Test.Validators.CustomTypes
        )

      {:ok, pid2} =
        Kungfuig.start_link(
          name: IsolatedInstance2,
          callback: self()
        )

      # Valid config for instance1 (with validator)
      valid_config = %{
        string_value: "test",
        integer_value: 42,
        float_value: 3.14,
        boolean_value: true,
        array_value: ["one", "two"],
        map_value: %{key: "value"}
      }

      Application.put_env(:isolated_instance1, :config, valid_config)

      assert_receive {:kungfuig_update,
                      %{env: %{isolated_instance1: [config: %{string_value: "test"}]}}},
                     1_100

      # Same config structure should work for instance2 (no validator)
      Application.put_env(:isolated_instance2, :config, valid_config)

      assert_receive {:kungfuig_update,
                      %{env: %{isolated_instance2: [config: %{string_value: "test"}]}}},
                     1_100

      # Invalid config should fail for instance1 but work for instance2
      invalid_config = %{
        # should be string
        string_value: 123,
        # should be integer
        integer_value: "42"
      }

      Application.put_env(:isolated_instance1, :config, invalid_config)

      refute_receive {:kungfuig_update,
                      %{env: %{isolated_instance1: [config: %{string_value: 123}]}}},
                     1_100

      Application.put_env(:isolated_instance2, :config, invalid_config)

      assert_receive {:kungfuig_update,
                      %{env: %{isolated_instance2: [config: %{string_value: 123}]}}},
                     1_100

      # Clean up
      Application.delete_env(:isolated_instance1, :config)
      Application.delete_env(:isolated_instance2, :config)
      Supervisor.stop(pid1)
      Supervisor.stop(pid2)
    end
  end

  describe "configuration options" do
    test "different interval settings" do
      test_pid = self()

      # Test with short interval
      {:ok, pid1} =
        Kungfuig.start_link(
          name: FastInterval,
          interval: 100,
          imminent: false,
          callback: fn config -> send(test_pid, {:fast_update, config}) end
        )

      # Test with longer interval
      {:ok, pid2} =
        Kungfuig.start_link(
          name: SlowInterval,
          interval: 500,
          imminent: false,
          callback: fn config -> send(test_pid, {:slow_update, config}) end
        )

      # Set config and measure timing
      start_time = System.monotonic_time(:millisecond)
      Application.put_env(:kungfuig, :interval_test, %{value: "test"})

      # Fast interval should receive update quickly
      assert_receive {:fast_update, _}, 200
      fast_time = System.monotonic_time(:millisecond) - start_time

      # Slow interval should take longer
      assert_receive {:slow_update, _}, 600
      slow_time = System.monotonic_time(:millisecond) - start_time

      # Verify timing differences
      assert fast_time <= slow_time

      Application.delete_env(:kungfuig, :interval_test)
      Supervisor.stop(pid1)
      Supervisor.stop(pid2)
    end

    test "imminent validation option" do
      test_pid = self()

      # Test with imminent validation
      {:ok, _pid1} =
        Kungfuig.start_link(
          name: ImmediateValidation,
          imminent: true,
          validator: Kungfuig.Test.Validators.CustomTypes,
          callback: fn config -> send(test_pid, {:immediate, config}) end
        )

      # Should receive update immediately without waiting for interval
      assert_receive {:immediate, _}, 50

      # Test without imminent validation
      {:ok, _pid2} =
        Kungfuig.start_link(
          name: DelayedValidation,
          imminent: false,
          interval: 500,
          validator: Kungfuig.Test.Validators.CustomTypes,
          callback: fn config -> Process.sleep(10) && send(test_pid, {:delayed, config}) end
        )

      # Should wait for the interval
      refute_received {:delayed, _}
      assert_receive {:delayed, _}, 600
    end

    @tag skip: "Erlang DBG output, run manually to ensure"
    test "start_options propagation" do
      # Test with custom start options
      {:ok, pid} =
        Kungfuig.start_link(
          name: StartOpts,
          start_options: [debug: [:trace]],
          callback: self()
        )

      # Verify process is traced
      {_, blender_pid, _, _} =
        pid
        |> Supervisor.which_children()
        |> Enum.find(&match?({Kungfuig.Blender, _, _, _}, &1))

      {:status, _, {:module, :gen_server}, [_, _, _, _, state]} = :sys.get_status(blender_pid)
      Process.sleep(10)

      assert get_in(state, [:data, Access.filter(&match?({~c"Status", _}, &1))]) ==
               [{~c"Status", :running}]

      Supervisor.stop(pid)
    end

    test "different worker configurations" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: WorkerConfig,
          workers: [
            Kungfuig.Backends.Env,
            {Kungfuig.Backends.EnvTransform,
             interval: 100, validator: Kungfuig.Validators.EnvTransform},
            {Kungfuig.Test.Backends.Custom, interval: 200, validator: Kungfuig.Validators.Void}
          ],
          callback: self()
        )

      assert_receive {:kungfuig_update, %{custom: [custom_value: "from custom backend"]}}, 1_100

      Supervisor.stop(pid)
    end

    test "worker restart behavior" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: WorkerRestart,
          workers: [
            {Kungfuig.Backends.Env, interval: 100}
          ],
          callback: self()
        )

      # Get worker pid
      [{worker_id, worker_pid, :worker, _}] =
        WorkerRestart
        |> Supervisor.which_children()
        |> Enum.filter(&match?({_, _, :worker, _}, &1))

      # Kill worker
      Process.exit(worker_pid, :kill)

      # Worker should be restarted
      Process.sleep(200)

      [{^worker_id, new_worker_pid, :worker, _}] =
        WorkerRestart
        |> Supervisor.which_children()
        |> Enum.filter(&match?({_, _, :worker, _}, &1))

      assert worker_pid != new_worker_pid
      assert Process.alive?(new_worker_pid)

      Supervisor.stop(pid)
    end
  end

  describe "json kungfuig" do
    test "custom target with via registered name" do
      {:ok, pid} =
        Kungfuig.start_link(
          name: KfJson,
          workers: [
            {Kungfuig.Backends.Json, interval: 100, for: "priv"}
          ],
          callback: self()
        )

      assert_receive {:kungfuig_update,
                      %{
                        json: %{
                          "file1.json" => %{
                            "list" => [42, 3.14, "foo"],
                            "map" => %{"item1" => 42, "item2" => "foo"},
                            "name" => "file1"
                          },
                          "file2.json" => %{
                            "list" => [42, 3.14, {:foo, 42}],
                            "map" => %{"item1" => fun, "item2" => :foo},
                            "name" => "file1"
                          }
                        }
                      }}

      assert [module: IO, name: :inspect, arity: 1, env: [], type: :external] ==
               Function.info(fun)

      Supervisor.stop(pid)
    end
  end

  describe "error conditions" do
    @tag :skip
    test "invalid callback configurations" do
      # Test invalid callback module
      assert_raise RuntimeError, ~r/Expected callable/, fn ->
        Kungfuig.start_link(
          name: InvalidCallback1,
          callback: :not_a_valid_callback
        )
      end

      # Test invalid callback tuple format
      assert_raise RuntimeError, ~r/Expected callable/, fn ->
        Kungfuig.start_link(
          name: InvalidCallback2,
          callback: {TestModule, :function, :extra_arg}
        )
      end

      # Test invalid GenServer message type
      assert_raise RuntimeError, ~r/Expected callable/, fn ->
        Kungfuig.start_link(
          name: InvalidCallback3,
          callback: {self(), {:invalid_type, :message}}
        )
      end
    end

    test "invalid validator configurations" do
      # Test with invalid validator module
      # assert_raise UndefinedFunctionError, fn ->
      #   Kungfuig.start_link(
      #     name: InvalidValidator1,
      #     validator: InvalidModule,
      #     callback: self()
      #   )
      # end

      defmodule InvalidValidator do
        def validate(_), do: :invalid_return
      end

      # Test with validator returning invalid format
      {:ok, pid} =
        Kungfuig.start_link(
          name: InvalidValidator2,
          validator: InvalidValidator,
          callback: self()
        )

      log =
        capture_log(fn ->
          Application.put_env(:invalid_validator2, :invalid_test, "test")
          refute_receive {:kungfuig_update, _}, 1_100
        end)

      assert log =~ ":invalid_return"

      Application.delete_env(:invalid_validator2, :invalid_test)
      Supervisor.stop(pid)
    end

    test "worker error recovery" do
      defmodule FailingBackend do
        use Kungfuig.Backend, name: :failing

        @impl true
        def get(_meta) do
          if :rand.uniform() > 0.5 do
            {:error, "Random failure"}
          else
            {:ok, %{value: "success"}}
          end
        end
      end

      {:ok, pid} =
        Kungfuig.start_link(
          name: ErrorRecovery,
          workers: [
            {FailingBackend, interval: 100}
          ],
          callback: self()
        )

      # Let it run for a while to catch both success and failure cases
      log =
        capture_log(fn ->
          Process.sleep(500)
        end)

      # Should see error messages but process should stay alive
      assert log =~ "Random failure" or
               (receive do
                  {:kungfuig_update, _} -> true
                after
                  600 -> false
                end)

      assert Process.alive?(pid)
      Supervisor.stop(pid)
    end
  end
end
