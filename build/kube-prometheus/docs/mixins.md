# Adding Mixins

## Installing a new mixin

Install the mixin into each kube-prometheus release directory:

```sh
cd build/kube-prometheus/libraries/<version-of-kube-prometheus>
jb install github.com/bitnami-labs/sealed-secrets/contrib/prometheus-mixin@main
```

## Adding the mixin to common-template.jsonnet

Add the import to `common-template.jsonnet`. For example, for the Bitnami sealed-secrets mixin:

```diff
@@ -46,6 +46,7 @@ local kp =
   // (import 'kube-prometheus/addons/static-etcd.libsonnet') +
   // (import 'kube-prometheus/addons/custom-metrics.libsonnet') +
   // (import 'kube-prometheus/addons/external-metrics.libsonnet') +
+  (import 'github.com/bitnami-labs/sealed-secrets/contrib/prometheus-mixin/mixin.libsonnet') +

   {
     values+:: {
```

The search path is relative to the top of the `vendor` folder. Check how the `velero` mixin is added in `common-template.jsonnet` for reference.

Enable/disable the mixin via the `addMixins` field in your cluster vars file:

```jsonnet
addMixins: {
  ceph: true,
  sealedsecrets: true,
  velero: false,
  'cert-manager': true,
},
```

## Adding a custom Prometheus rule as a mixin

Create a `mixin.libsonnet` in the relevant folder under `mixins/` and generate `prometheus.yaml`:

```sh
jsonnet -e '(import "mixin.libsonnet").prometheusAlerts' | gojsontoyaml > prometheus.yaml
```

Verify the generated file is valid:

```sh
promtool check rules build/kube-prometheus/mixins/${NEW_RULE}/prometheus.yaml
```

Verify the rules work as intended:

```sh
promtool test rules build/kube-prometheus/mixins/${NEW_RULE}/{TEST_FILE}.yaml
```

The actual rule is generated into your kubeaid-config repo via `build.sh`. To test whether an alert fires, apply the generated YAML to your test cluster:

```sh
kubectl apply -f <path to alert rules file>.yaml -n monitoring
```
