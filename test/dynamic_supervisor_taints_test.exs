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
        delta_crdt_options: [sync_interval: 20]
      )

    {:ok, _} =
      Horde.DynamicSupervisor.start_link(
        name: n2,
        strategy: :one_for_one,
        delta_crdt_options: [sync_interval: 20]
      )

    {:ok, _} =
      Horde.DynamicSupervisor.start_link(
        name: n3,
        strategy: :one_for_one,
        delta_crdt_options: [sync_interval: 20]
      )

    Horde.Cluster.set_members(n1, [n1, n2, n3])

    # give the processes a couple ms to sync up
    Process.sleep(100)

    [n1: n1, n2: n2, n3: n3]
  end

  test "doesn't start a process on a tainted node", %{n1: n1, n2: n2, n3: n3} do
    proc_count = 10_000

    :ok = Horde.DynamicSupervisor.taint(n1)
    Process.sleep(100)

    for i <- 1..proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    count1 = count_local_children(n1)
    count2 = count_local_children(n2)
    count3 = count_local_children(n3)

    assert count1 == 0
    assert count2 + count3 == proc_count
  end

  test "tainted node is still tainted when it re-joins the cluster", %{n1: n1, n2: n2, n3: n3} do
    proc_count = 10_000

    :ok = Horde.DynamicSupervisor.taint(n1)
    Process.sleep(100)

    for i <- 1..proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    count1 = count_local_children(n1)
    count2 = count_local_children(n2)
    count3 = count_local_children(n3)

    assert count1 == 0
    assert count2 + count3 == proc_count

    # Remove node from the cluster.
    :ok = Horde.Cluster.set_members(n1, [n1])

    eventually(fn ->
      Horde.DynamicSupervisor.count_children(n1).active == 0
    end)

    # Add the node back to the cluster.
    :ok = Horde.Cluster.set_members(n1, [n1, n2, n3])

    eventually(fn ->
      Horde.DynamicSupervisor.count_children(n1).active == proc_count
    end)

    for i <- 1..proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    count1 = count_local_children(n1)
    count2 = count_local_children(n2)
    count3 = count_local_children(n3)

    assert count1 == 0
    assert count2 + count3 == proc_count * 2
  end

  test "doesn't migrate processes to the tainted node after a node goes down", %{
    n1: n1,
    n2: n2,
    n3: n3
  } do
    proc_count = 100

    :ok = Horde.DynamicSupervisor.taint(n1)
    Process.sleep(100)

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
    count3 = count_local_children(n3) |> IO.inspect(label: "count3")

    Process.flag(:trap_exit, true)
    Horde.DynamicSupervisor.stop(n3, :shutdown)

    eventually(
      fn ->
        count1 = count_local_children(n1)
        count2 = count_local_children(n2)

        assert count1 == 0
        assert count2 == proc_count
      end,
      250,
      100
    )
  end

  # test "doesn't start the process if only tainted nodes are available"
  # test "doesn't restart crashed process if only tainted nodes are available"
  # test "doesn't actively handoff processes when node becomes tainted"
  # test "doesn't handoff processes to tainted nodes during rebalancing"
  # test "processes are started on untainted node"
  # test "node that's untainted outside of the cluter joins the cluster as untainted"
  # test taint on startup

  defp count_local_children(dynamic_sup) do
    proc_sup_name = :"#{dynamic_sup}.ProcessesSupervisor"
    Supervisor.count_children(proc_sup_name).active
  end

  defp make_child_spec(i) do
    random_state = :rand.uniform(100_000_000)
    %{id: i, start: {Agent, :start_link, [fn -> random_state end]}}
  end
end
