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
           name: Server1Blender,
           interval: 100,
           validator: Kungfuig.Validators.Env,
           callback: {self(), {:info, :updated}}}
      )

    assert_receive {:updated, %{env: %{kungfuig: []}}}, 1_100

    Application.put_env(:kungfuig, :foo, 42)

    assert_receive {:updated, %{env: %{kungfuig: [foo: 42]}}}, 1_100

    System.put_env("KUNGFUIG_FOO", "42")
    assert_receive {:updated, %{system: %{"KUNGFUIG_FOO" => "42"}}}, 1_100

    assert Kungfuig.config(:!, KF1) == %{
             env: %{kungfuig: [foo: 42]},
             system: %{"KUNGFUIG_FOO" => "42"}
           }

    Application.delete_env(:kungfuig, :foo)
    System.delete_env("KUNGFUIG_FOO")
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

    assert_receive {:updated, %{env_transform: []}}, 120

    Application.put_env(:kungfuig, :foo_transform, %{bar: :baz})
    assert_receive {:updated, %{env_transform: [foo_transform: :baz]}}, 120
    assert Kungfuig.config() == %{env_transform: [foo_transform: :baz]}

    assert capture_log([level: :info], fn ->
             Application.put_env(:kungfuig, :foo_transform, %{bar: 42})
             refute_receive({:updated, %{env_transform: [foo_transform: 42]}}, 120)
           end) =~ "atom, got: 42"

    assert Kungfuig.config() == %{env_transform: [foo_transform: :baz]}

    Application.delete_env(:kungfuig, :foo_transform)
    Supervisor.stop(pid)
  end

  test "custom target with via registered name" do
    {:ok, pid} =
      Kungfuig.start_link(
        name: KF2,
        blender:
          {Kungfuig.Blender,
           interval: 100,
           validator: Kungfuig.Validators.Env,
           callback: {self(), {:info, :updated}}}
      )

    assert_receive {:updated, %{env: %{kungfuig: []}}}, 1_100

    Application.put_env(:kungfuig, :bar, 24)

    assert_receive {:updated, %{env: %{kungfuig: [bar: 24]}}}, 1_100

    System.put_env("KUNGFUIG_BAR", "24")
    assert_receive {:updated, %{system: %{"KUNGFUIG_BAR" => "24"}}}, 1_100

    assert Kungfuig.config(nil, KF2) == %{
             env: %{kungfuig: [bar: 24]},
             system: %{"KUNGFUIG_BAR" => "24"}
           }

    Application.delete_env(:kungfuig, :bar)
    System.delete_env("KUNGFUIG_BAR")
    Supervisor.stop(pid)
  end
end
