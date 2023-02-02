defmodule DynamicSupervisorTaintsTest do
  require Logger
  use ExUnit.Case
  import Liveness

  @proc_count 1000
  @common_opts [strategy: :one_for_one, delta_crdt_options: [sync_interval: 20]]

  test "doesn't start a process on a tainted node" do
    [n1, n2, n3] = setup_cluster(3, @common_opts)
    :ok = Horde.DynamicSupervisor.taint(n1)
    Process.sleep(100)

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    count1 = count_local_children(n1)
    count2 = count_local_children(n2)
    count3 = count_local_children(n3)

    assert count1 == 0
    assert count2 + count3 == @proc_count
  end

  test "tainted node is still tainted when it re-joins the cluster" do
    [n1, n2, n3] = setup_cluster(3, @common_opts)
    :ok = Horde.DynamicSupervisor.taint(n1)
    Process.sleep(100)

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    count1 = count_local_children(n1)
    count2 = count_local_children(n2)
    count3 = count_local_children(n3)

    assert count1 == 0
    assert count2 + count3 == @proc_count

    uncluster(n1, [n2, n3])
    cluster([n1, n2, n3])

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    count1 = count_local_children(n1)
    count2 = count_local_children(n2)
    count3 = count_local_children(n3)

    assert count1 == 0
    assert count2 + count3 == @proc_count * 2
  end

  test "doesn't migrate processes to the tainted node after a node goes down" do
    [n1, n2, n3] = setup_cluster(3, @common_opts)
    :ok = Horde.DynamicSupervisor.taint(n1)
    Process.sleep(100)

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    eventually(fn ->
      Horde.DynamicSupervisor.count_children(n1).active == @proc_count
    end)

    Process.flag(:trap_exit, true)
    Horde.DynamicSupervisor.stop(n3, :shutdown)

    eventually(
      fn ->
        count1 = count_local_children(n1)
        count2 = count_local_children(n2)

        assert count1 == 0
        assert count2 == @proc_count
      end,
      250,
      100
    )
  end

  test "doesn't start the process if only tainted members are available" do
    [n1, n2, n3] = setup_cluster(3, @common_opts)
    :ok = Horde.DynamicSupervisor.taint(n1)
    :ok = Horde.DynamicSupervisor.taint(n2)
    :ok = Horde.DynamicSupervisor.taint(n3)
    Process.sleep(100)

    for sup <- [n1, n2, n3] do
      assert {:error, :no_alive_nodes} =
               Horde.DynamicSupervisor.start_child(sup, make_child_spec(1))
    end
  end

  test "the process is lost when its member goes down and only tainted members are available" do
    # given
    [n1, n2, n3] = setup_cluster(3, @common_opts)
    assert {:ok, _} = Horde.DynamicSupervisor.start_child(n1, make_child_spec(1))

    :ok = Horde.DynamicSupervisor.taint(n1)
    :ok = Horde.DynamicSupervisor.taint(n2)
    :ok = Horde.DynamicSupervisor.taint(n3)

    [sup] = Enum.filter([n1, n2, n3], &(count_local_children(&1) == 1))

    # when
    Process.flag(:trap_exit, true)
    Horde.DynamicSupervisor.stop(sup, :shutdown)

    # then
    assert_raise Liveness, fn ->
      eventually(fn ->
        Horde.DynamicSupervisor.count_children(n1).active > 0
      end)
    end
  end

  test "doesn't actively handoff processes when member becomes tainted" do
    # given
    [n1, n2, n3] = setup_cluster(3, @common_opts)

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    count1 = count_local_children(n1)
    assert count1 > 0
    assert count_local_children(n2) > 0
    assert count_local_children(n3) > 0

    # when
    Horde.DynamicSupervisor.taint(n1)

    # then
    assert_raise Liveness, fn ->
      eventually(fn ->
        count_local_children(n1) != count1
      end)
    end
  end

  test "processes are started on untainted member" do
    # given
    [n1, n2, n3] = setup_cluster(3, @common_opts)
    Horde.DynamicSupervisor.taint(n1)

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    assert count_local_children(n1) == 0
    assert count_local_children(n2) > 0
    assert count_local_children(n3) > 0

    # when
    Horde.DynamicSupervisor.untaint(n1)

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    # then
    eventually(fn ->
      count1 = count_local_children(n1)
      count2 = count_local_children(n2)
      count3 = count_local_children(n3)

      assert count1 > 0
      assert count1 + count2 + count3 == 2 * @proc_count
    end)
  end

  test "member that's untainted outside of the cluter joins the cluster as untainted" do
    # given
    [n1, n2, n3] = setup_cluster(3, @common_opts)
    Horde.DynamicSupervisor.taint(n1)

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    assert count_local_children(n1) == 0
    assert count_local_children(n2) > 0
    assert count_local_children(n3) > 0

    # when
    uncluster(n1, [n2, n3])

    Horde.DynamicSupervisor.untaint(n1)

    cluster([n1, n2, n3])

    for i <- 1..@proc_count do
      sup = Enum.random([n1, n2, n3])
      child_spec = make_child_spec(i)

      {:ok, _} = Horde.DynamicSupervisor.start_child(sup, child_spec)
    end

    # then
    eventually(fn ->
      count1 = count_local_children(n1)
      count2 = count_local_children(n2)
      count3 = count_local_children(n3)

      assert count1 > 0
      assert count1 + count2 + count3 == 2 * @proc_count
    end)
  end

  test "member can be initialized as tainted" do
    members = setup_cluster(3, [{:tainted, true} | @common_opts])
    child_spec = make_child_spec(1)

    for m <- members do
      assert {:error, :no_alive_nodes} = Horde.DynamicSupervisor.start_child(m, child_spec)
    end
  end

  defp setup_cluster(size, opts) do
    members =
      for i <- 1..size do
        name = :"horde_#{i}"
        opts = Keyword.put(opts, :name, name)

        start_supervised!({Horde.DynamicSupervisor, opts})

        name
      end

    cluster(members)

    members
  end

  defp count_local_children(dynamic_sup) do
    proc_sup_name = :"#{dynamic_sup}.ProcessesSupervisor"
    Supervisor.count_children(proc_sup_name).active
  end

  defp make_child_spec(i) do
    random_state = :rand.uniform(100_000_000)
    %{id: i, start: {Agent, :start_link, [fn -> random_state end]}}
  end

  # We use custom function because transitive clustering (i.e. setting the cluster
  # through a single member) doesn't work after a member has been unclustered.
  def cluster(members) do
    Enum.each(members, fn m ->
      Horde.Cluster.set_members(m, members)
    end)

    eventually(fn ->
      Enum.each(members, fn m ->
        assert length(Horde.Cluster.members(m)) == length(members)
      end)
    end)
  end

  def uncluster(member, members_left) do
    Horde.Cluster.set_members(member, [member])
    Enum.each(members_left, &Horde.Cluster.set_members(&1, members_left))

    eventually(fn ->
      assert length(Horde.Cluster.members(member)) == 1

      Enum.each(members_left, fn m ->
        assert length(Horde.Cluster.members(m)) == length(members_left)
      end)
    end)
  end
end
