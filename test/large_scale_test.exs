defmodule DynamicSupervisorTaintsTest do
  require Logger
  use ExUnit.Case
  import Liveness

  setup do
    n1 = :horde_1
    n2 = :horde_2
    n3 = :horde_3

    {:ok, _} =
      Horde.DynamicSupervisor.start_link(
        name: n1,
        strategy: :one_for_one,
        delta_crdt_options: [sync_interval: 100]
      )

    {:ok, _} =
      Horde.DynamicSupervisor.start_link(
        name: n2,
        strategy: :one_for_one,
        delta_crdt_options: [sync_interval: 100]
      )

    {:ok, _} =
      Horde.DynamicSupervisor.start_link(
        name: n3,
        strategy: :one_for_one,
        delta_crdt_options: [sync_interval: 100]
      )

    Horde.Cluster.set_members(n1, [n1, n2, n3])

    # give the processes a couple ms to sync up
    Process.sleep(100)

    [n1: n1, n2: n2, n3: n3]
  end

  test "migration after shutdown", %{
    n1: n1,
    n2: n2,
    n3: n3
  } do
    proc_count = 10_000

    for i <- 1..proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    eventually(fn ->
      Horde.DynamicSupervisor.count_children(n1).active == proc_count
    end)

    count1 = count_local_children(n1) |> IO.inspect(label: "count1")
    count2 = count_local_children(n2) |> IO.inspect(label: "count2")
    count3 = count_local_children(n2) |> IO.inspect(label: "count2")

    Process.flag(:trap_exit, true)
    Horde.DynamicSupervisor.stop(n3, :shutdown)

    eventually(
      fn ->
        count1 = count_local_children(n1) |> IO.inspect(label: "count1")
        count2 = count_local_children(n2) |> IO.inspect(label: "count2")

        assert count1 + count2 == proc_count
      end,
      250,
      100
    )
  end

  defp count_local_children(dynamic_sup) do
    proc_sup_name = :"#{dynamic_sup}.ProcessesSupervisor"
    Supervisor.count_children(proc_sup_name).active
  end

  defp make_child_spec(i) do
    random_state = :rand.uniform(100_000_000)
    %{id: i, start: {Agent, :start_link, [fn -> random_state end]}}
  end
end
