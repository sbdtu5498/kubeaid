# Hetzner Provider : Hybrid mode

The `hetzner` provider, in `hybrid` mode, is used to provision a KubeAid managed Kubernetes cluster, with the control-plane in HCloud and node-groups in HCloud or Hetzner Bare Metal. We also setup the following for you :

- [Cilium](https://cilium.io) CNI, running in [kube-proxyless mode](https://cilium.io/use-cases/kube-proxy/).

- Node-groups, with **labels and taints propagation** support.
  > If the node-group is in HCloud, then it's autoscalable as well, with scale to / from 0 support.

- GitOps, using [ArgoCD](https://argoproj.github.io/cd/), [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) and [ClusterAPI](https://cluster-api.sigs.k8s.io).

- Monitoring, using [KubePrometheus](https://prometheus-operator.dev).

## Prerequisites

- Fork the [KubeAid Config](https://github.com/Obmondo/kubeaid-config) repository.

- Keep your Git provider credentials ready.
  > For GitHub, you can create a [Personal Access Token (PAT)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token), which has the permission to write to your KubeAid Config fork.
  > That PAT will be used as the password.

- Have [Docker](https://www.docker.com/products/docker-desktop/) running locally.

- [Create an HCloud SSH KeyPair](https://www.youtube.com/watch?v=mxN6fyMuQRI).
  > Remember, no 2 HCloud SSH KeyPairs can have the same SSH public key.

- Create a Hetzner Bare Metal SSH KeyPair, by visiting <https://robot.hetzner.com/key/index>.
  > Remember, no 2 Hetzner Bare Metal SSH KeyPairs can have the same SSH public key.

- If you're going to set `cloud.hetzner.bareMetal.wipeDisks: True` in `general.config.yaml`, then remove any pre-existing RAID setup from the corresponding your Hetzner Bare Metal servers.

  You can do so, by executing the `wipefs -fa <partition-name>` for each partition in each Hetzner Bare Metal server.

## Disk layout for Hetzner Bare Metal servers

For each Hetzner Bare Metal server, we have **level 1** `SWRAID` (Software RAID) enabled across disks whose WWNs you've specified in the general config file. And, by default, on top of that level 1 SWRAID, we create a 25G sized `Logical Volume Group` (LVG) named **vg0**. It contains the 10G sized **root** `Volume Group` (VG), where the Operating System gets installed.
> If you have HDDs attached to the server, then we recommend you specify their WWNs in the general config file. So the OS will get installed there, and, you'll have your SSDs / NVMes solely dedicated to your stateful workloads.

Now, you can configure the disk layout further, via the `diskLayoutSetupCommands` option in the general config file.

We recommend :

- allocating your HDDs / SSDs to `Ceph`.

- allocating your NVMes to a ZPool (running in `mirror mode`), shared by ContainerD image store, Kubernetes pod logs and ephemeral volumes and `OpenEBS ZFS LocalPV provisioner`.

## Installation

```bash
KUBEAID_CLI_VERSION=$(curl -s "https://api.github.com/repos/Obmondo/kubeaid-cli/releases/latest" | jq -r .tag_name)
OS=$([ "$(uname -s)" = "Linux" ] && echo "linux" || echo "darwin")
CPU_ARCHITECTURE=$([ "$(uname -m)" = "x86_64" ] && echo "amd64" || echo "arm64")

wget "https://github.com/Obmondo/kubeaid-cli/releases/download/${KUBEAID_CLI_VERSION}/kubeaid-cli-${KUBEAID_CLI_VERSION}-${OS}-${CPU_ARCHITECTURE}"
sudo mv kubeaid-cli-${KUBEAID_CLI_VERSION}-${OS}-${CPU_ARCHITECTURE} /usr/local/bin/kubeaid-cli
sudo chmod +x /usr/local/bin/kubeaid-cli
```

## Preparing the Configuration Files

You need to have 2 configuration files : `general.yaml` and `secrets.yaml` containing required credentials.

Run :
```shell script
kubeaid-cli config generate hetzner hybrid
```
and a sample of those 2 configuration files will be generated in `outputs/configs`.

Edit those 2 configuration files, based on your requirements.

## Bootstrapping the Cluster

Run the following command, to bootstrap the cluster :
```shell script
kubeaid-cli cluster bootstrap
```

Aside from the logs getting streamed to your standard output, they'll be saved in `outputs/.log`.

Once the cluster gets bootstrapped, its kubeconfig gets saved in `outputs/kubeconfigs/clusters/main.yaml`.

You can access the cluster, by running :
```shell script
export KUBECONFIG=./outputs/kubeconfigs/main.yaml
kubectl cluster-info
```
Go ahead and explore it by accessing the [ArgoCD]() and [Grafana]() dashboards.

## Deleting the Cluster

You can delete the cluster, by running :
```shell script
kubeaid-cli cluster delete main
kubeaid-cli cluster delete management
```
