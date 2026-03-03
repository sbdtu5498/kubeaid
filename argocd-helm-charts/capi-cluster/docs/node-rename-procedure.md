## Changing Node Names using Cluster API

Kubernetes node names are immutable. In a Cluster API (CAPI) managed cluster, renaming a node requires recreating it.
This process deletes and reprovisions the node with the updated name.

> Warning: The node will be wiped. Any local (non-persistent) data will be lost. Ensure backups are in place.

### Steps

**1. Identify the Node**

Login to the cluster in which you need to conduct node renaming.
Every cluster which is set up by Cluster API, have cluster api resources running in the cluster.

It's CAPH in case of hetzner bare-metal servers

List CAPI machines:

```shell
    kubectl get machines -n capi-cluster
```

If using Hetzner Bare Metal:

```shell
    kubectl get hetznerbaremetalmachines -n capi-cluster
```

**2. Drain the Node**

```shell
    kubectl cordon <node-name>
    kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

**3. Delete CAPI Resources**

Delete the Machine:

```shell
    kubectl delete machine <machine-name> -n capi-cluster
```

Delete the hetznerbaremetalmachine too if it's hetzner bare-metal:

```shell
    kubectl delete hetznerbaremetalmachine <resource-name> -n capi-cluster
```

CAPI will automatically reprovision the node.

**4. Monitor Reprovisioning**

It takes around 5-15 minutes for the node to reprovision again. you should monitor to identify any potential bugs

```shell
    kubectl get machines -n capi-cluster -w
    kubectl get nodes
```

Confirm the new node joins and reaches Ready status.

**5. Handle Rook Ceph (if installed)**

Incase you rook ceph setup in cluster, you would need to perform few additional steps. Follow [this](#rook-ceph)

### Rook ceph

1. Go to rook-ceph namespace and then list down OSD related pods

2. You will see few OSD pods are down - which is most likely there because it's still pointing to older node names and you need to update these to point to latest node names

3. Exec into rook-ceph-tools pod -> run this command -> ```ceph osd crush rename-bucket <old-node-name> <new-node-name>```

4. Proceed to editing parent resource of OSD related pods (for example - deployment, statefulset) and change node names to latest one

5. Inspect the logs and run this command to ensure health is okay

```shell
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph health detail
```
