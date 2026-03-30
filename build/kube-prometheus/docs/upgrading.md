# Upgrading

## Upgrading to a new kube-prometheus version

Change the `kube_prometheus_version` field in your cluster vars file (e.g. `k8s/<cluster-name>/<cluster-name>-vars.jsonnet`) and run the build script again:

```sh
./build/kube-prometheus/build.sh ../<your-kubeaid-config>/k8s/<cluster-name>
```

The script checks if the version directory already exists under `build/kube-prometheus/libraries/`. If not, it downloads the dependencies first, then builds the manifests. This way you can upgrade or downgrade with ease.

If `kube_prometheus_version` is not set in the vars file, it defaults to `main`.

## Updating vendor dependencies

To update vendor directories for all existing versions:

```sh
./build/kube-prometheus/update.sh
```

## Adding a new version

If a kube-prometheus version isn't already present in KubeAid, run:

```sh
./build/kube-prometheus/add-version.sh <version-tag>
```

## Cleaning up broken vendor directories

If you encounter broken version dependencies, delete the version directory and re-run the build script:

```sh
rm -rf ./build/kube-prometheus/libraries/v0.16.0/
./build/kube-prometheus/build.sh ../<your-kubeaid-config>/k8s/<cluster-name>
```

> **NOTE:** v0.16.0 is a special release. The upstream kube-prometheus v0.16.0 had an issue which was resolved by pointing to this patch commit: [prometheus-operator/kube-prometheus#2733](https://github.com/prometheus-operator/kube-prometheus/pull/2733)
