defmodule ClusterTest do
  use ExUnit.Case, async: false
  import Liveness

  describe "members option" do
    test "can join registry by specifying members in init" do
      {:ok, _} =
        Horde.Registry.start_link(
          name: :reg4,
          keys: :unique,
          members: [:reg4, :reg5],
          delta_crdt_options: [sync_interval: 10]
        )

      {:ok, _} =
        Horde.Registry.start_link(
          name: :reg5,
          keys: :unique,
          members: [:reg4, :reg5],
          delta_crdt_options: [sync_interval: 10]
        )

      members = Horde.Cluster.members(:reg4)
      assert 2 = Enum.count(members)
    end

    test "can join supervisor by specifying members in init" do
      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup4,
          strategy: :one_for_one,
          members: [:sup4, :sup5],
          delta_crdt_options: [sync_interval: 10]
        )

      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup5,
          strategy: :one_for_one,
          members: [:sup4, :sup5],
          delta_crdt_options: [sync_interval: 10]
        )

      members = Horde.Cluster.members(:sup4)
      assert 2 = Enum.count(members)
    end
  end

  describe ".members/1" do
    test "Registry returns same thing after setting members twice" do
      {:ok, _reg1} =
        Horde.Registry.start_link(
          name: :reg0,
          keys: :unique,
          delta_crdt_options: [sync_interval: 10]
        )

      assert :ok = Horde.Cluster.set_members(:reg0, [:reg00, :reg0])
      assert [{:reg0, node()}, {:reg00, node()}] == Horde.Cluster.members(:reg0)
      assert :ok = Horde.Cluster.set_members(:reg0, [:reg00, :reg0])
      assert [{:reg0, node()}, {:reg00, node()}] == Horde.Cluster.members(:reg0)
    end

    test "Supervisor returns same thing after setting members twice" do
      {:ok, _reg1} =
        Horde.DynamicSupervisor.start_link(
          name: :sup0,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 10]
        )

      assert :ok = Horde.Cluster.set_members(:sup0, [:sup00, :sup0])
      assert [{:sup0, node()}, {:sup00, node()}] == Horde.Cluster.members(:sup0)
      assert :ok = Horde.Cluster.set_members(:sup0, [:sup00, :sup0])
      assert [{:sup0, node()}, {:sup00, node()}] == Horde.Cluster.members(:sup0)
    end
  end

  describe ".set_members/2" do
    test "returns true when registries joined" do
      {:ok, _reg1} =
        Horde.Registry.start_link(
          name: :reg1,
          keys: :unique,
          delta_crdt_options: [sync_interval: 10]
        )

      {:ok, _reg2} =
        Horde.Registry.start_link(
          name: :reg2,
          keys: :unique,
          delta_crdt_options: [sync_interval: 10]
        )

      assert :ok = Horde.Cluster.set_members(:reg1, [:reg1, :reg2])
    end

    test "returns true when supervisors joined" do
      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup1,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 10]
        )

      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup2,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 10]
        )

      assert :ok = Horde.Cluster.set_members(:sup1, [:sup1, :sup2])
    end

    test "returns true when other registry doesn't exist" do
      {:ok, _reg3} =
        Horde.Registry.start_link(
          name: :reg3,
          keys: :unique,
          delta_crdt_options: [sync_interval: 10]
        )

      assert :ok = Horde.Cluster.set_members(:reg3, [:reg3, :doesnt_exist], 100)
    end

    test "returns true when other supervisor doesn't exist" do
      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup3,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 10]
        )

      assert :ok = Horde.Cluster.set_members(:sup3, [:sup3, :doesnt_exist], 100)
    end

    test "can join and unjoin supervisor with set_members" do
      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup6,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 10]
        )

      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup7,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 10]
        )

      assert :ok = Horde.Cluster.set_members(:sup6, [:sup6, :sup7])

      members = Horde.Cluster.members(:sup6)
      assert 2 = Enum.count(members)

      Process.sleep(50)

      assert :ok = Horde.Cluster.set_members(:sup6, [:sup6])

      [sup6: _nonode] = Horde.Cluster.members(:sup6)
    end

    test "can join and unjoin registry with set_members" do
      {:ok, _} =
        Horde.Registry.start_link(
          name: :reg6,
          keys: :unique,
          delta_crdt_options: [sync_interval: 10]
        )

      {:ok, _} =
        Horde.Registry.start_link(
          name: :reg7,
          keys: :unique,
          delta_crdt_options: [sync_interval: 10]
        )

      assert :ok = Horde.Cluster.set_members(:reg6, [:reg6, :reg7])

      Process.sleep(200)

      members = Horde.Cluster.members(:reg6)
      assert 2 = Enum.count(members)

      assert :ok = Horde.Cluster.set_members(:reg6, [:reg4])

      Process.sleep(200)

      members = Horde.Cluster.members(:reg6)

      assert 1 = Enum.count(members)
    end

    test "supervisor can start child" do
      {:ok, _} = start_supervised({Horde.DynamicSupervisor, [name: :sup, strategy: :one_for_one]})
      assert :ok = Horde.Cluster.set_members(:sup, [:sup])
      {:ok, child_pid} = Horde.DynamicSupervisor.start_child(:sup, {Task, fn -> :ok end})
      assert is_pid(child_pid)
    end
  end

  describe "auto cluster membership" do
    setup do
      cluster = "cluster-#{:rand.uniform(1000)}"
      nodes = LocalCluster.start_nodes(cluster, 2)

      on_exit(fn ->
        :erpc.multicall(Node.list([:visible, :this]), Horde.NodeListener, :clear_all, [])
      end)

      {:ok, cluster: cluster, nodes: nodes, all_nodes: Enum.sort([node() | nodes])}
    end

    test "supervisor should be registered on all clusters", ctx do
      Horde.DynamicSupervisor.start_link(
        name: :auto_sup,
        strategy: :one_for_one,
        delta_crdt_options: [sync_interval: 10],
        members: :auto
      )

      Process.sleep(200)

      assert :auto_sup |> Horde.Cluster.members() |> Keyword.values() |> Enum.sort() ==
               ctx.all_nodes
    end

    test "registry should be registered on all clusters", ctx do
      Horde.Registry.start_link(
        name: :auto_reg,
        keys: :unique,
        members: :auto,
        delta_crdt_options: [sync_interval: 10]
      )

      Process.sleep(200)

      assert :auto_reg |> Horde.Cluster.members() |> Keyword.values() |> Enum.sort() ==
               ctx.all_nodes
    end

    test "a new node should be auto added to the cluster", ctx do
      Horde.DynamicSupervisor.start_link(
        name: :auto_sup_add,
        strategy: :one_for_one,
        delta_crdt_options: [sync_interval: 10],
        members: :auto
      )

      Process.sleep(500)

      [new] = LocalCluster.start_nodes("extra-cluster", 1)

      Process.sleep(500)

      assert :auto_sup_add |> Horde.Cluster.members() |> Keyword.values() |> Enum.sort() ==
               Enum.sort([new | ctx.all_nodes])
    end

    test "a dead node should be auto removed from the cluster", ctx do
      Horde.Registry.start_link(
        name: :auto_reg_remove,
        keys: :unique,
        members: :auto,
        delta_crdt_options: [sync_interval: 10]
      )

      Process.sleep(500)

      LocalCluster.stop_nodes([hd(ctx.nodes)])

      Process.sleep(500)

      assert :auto_reg_remove |> Horde.Cluster.members() |> Keyword.values() |> Enum.sort() ==
               Enum.sort([node() | tl(ctx.nodes)])
    end
  end

  describe "starting and terminating children across cluster" do
    test "start_child is not blocked forever when remote member goes down" do
      # given
      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup8,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 1_000]
        )

      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup9,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 1_000]
        )

      :ok = Horde.Cluster.set_members(:sup8, [:sup8, :sup9])
      :ok = Horde.Cluster.set_members(:sup9, [:sup8, :sup9])
      eventually(fn -> supervisor_alive_member_count(:sup8) == 2 end)

      # when
      # Suspending the process simulates sup9 not responding to remote start_child via proxy_to_node.
      # However, in real life it shuts down, but it's irreproducible in local tests.
      :sys.suspend(:sup9)

      # then
      result =
        Enum.reduce_while(1..100, nil, fn _, _ ->
          try do
            {:ok, _} = Horde.DynamicSupervisor.start_child(:sup8, {Task, task_fun()})
            {:cont, :no_timeout}
          catch
            :exit, {:timeout, _} -> {:halt, :timeout}
          end
        end)

      assert result == :timeout
    end

    test "terminate_child is not blocked forever when remote member goes down" do
      # given
      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup10,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 10]
        )

      {:ok, _} =
        Horde.DynamicSupervisor.start_link(
          name: :sup11,
          strategy: :one_for_one,
          delta_crdt_options: [sync_interval: 10]
        )

      :ok = Horde.Cluster.set_members(:sup10, [:sup10, :sup11])
      :ok = Horde.Cluster.set_members(:sup11, [:sup10, :sup11])
      eventually(fn -> supervisor_alive_member_count(:sup10) == 2 end)

      children =
        Enum.map(1..100, fn _ ->
          {:ok, pid} = Horde.DynamicSupervisor.start_child(:sup10, {Task, task_fun(5_000)})
          pid
        end)

      # when
      :sys.suspend(:sup11)

      # then
      result =
        Enum.reduce_while(children, nil, fn pid, _ ->
          try do
            :ok = Horde.DynamicSupervisor.terminate_child(:sup10, pid)
            {:cont, :no_timeout}
          catch
            :exit, {:timeout, _} -> {:halt, :timeout}
          end
        end)

      assert result == :timeout
    end

    # every start_child needs an unique function, member to start the child on
    # is chosen based on child_spec hash
    defp task_fun(sleep \\ 0) do
      x = System.unique_integer()

      fn ->
        Process.sleep(sleep)
        x
      end
    end

    defp supervisor_alive_member_count(supervisor) do
      members = :sys.get_state(supervisor).members_info

      members
      |> Map.values()
      |> Enum.filter(fn %{status: status} -> status == :alive end)
      |> Enum.count()
    end
  end
end
