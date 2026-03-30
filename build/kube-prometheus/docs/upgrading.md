# Upgrading

## Upgrading to a new kube-prometheus version

Change the `kube_prometheus_version` field in your cluster vars file (e.g. `k8s/<cluster-name>/<cluster-name>-vars.jsonnet`) and run the build script again:

```sh
./build/kube-prometheus/build.sh ../<your-kubeaid-config>/k8s/<cluster-name>
```

The version directory must already exist under `build/kube-prometheus/libraries/`. If not, run `setup-version.sh` first.

If `kube_prometheus_version` is not set in the vars file, it defaults to `v0.17.0`.

## Updating a single mixin

To update a specific mixin to its latest upstream version (defaults to the latest release):

```sh
# Update a single mixin in the default version (v0.17.0)
./build/kube-prometheus/update-mixin.sh ceph-mixin

# Update a single mixin in a specific version
./build/kube-prometheus/update-mixin.sh ceph-mixin v0.13.0

# Update all direct dependencies
./build/kube-prometheus/update-mixin.sh --all

# List available mixin names
./build/kube-prometheus/update-mixin.sh --list
```

## Adding a new version

If a kube-prometheus version isn't already present in KubeAid, run:

```sh
./build/kube-prometheus/setup-version.sh <version-tag>
```

## Cleaning up broken vendor directories

If you encounter broken version dependencies, delete the version directory and re-run setup:

```sh
rm -rf ./build/kube-prometheus/libraries/v0.16.0/
./build/kube-prometheus/setup-version.sh v0.16.0
```

> **NOTE:** v0.16.0 is a special release. The upstream kube-prometheus v0.16.0 had an issue which was resolved by pointing to this patch commit: [prometheus-operator/kube-prometheus#2733](https://github.com/prometheus-operator/kube-prometheus/pull/2733)
