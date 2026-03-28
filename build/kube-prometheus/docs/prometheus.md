# Prometheus Operator Options

Options for `alertmanager`, `prometheus`, and other components can be tuned in your cluster vars file. Refer to the upstream sources for available fields:

- [alertmanager.libsonnet](https://github.com/prometheus-operator/kube-prometheus/blob/main/jsonnet/kube-prometheus/components/alertmanager.libsonnet) — kube-prometheus component defaults
- [AlertmanagerSpec API](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#alertmanagerspec) — all CR fields, accessible in jsonnet as `alertmanager.alertmanager.spec`
- [alertmanager-mixin config](https://github.com/prometheus/alertmanager/blob/main/doc/alertmanager-mixin/config.libsonnet) — mixin options

## Deleting metrics using Prometheus Admin APIs

Port-forward the Prometheus server:

```sh
kubectl port-forward pod/prometheus-k8s-0 -n monitoring 9090:9090
```

Ensure `web.enable-admin-api` is enabled — check at `http://localhost:9090/rules`.

Delete metrics via the admin API:

```sh
curl -X POST -g 'http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]=ceph_pool_metadata{job="job"}'
```

> **NOTE:** This does not delete metrics instantly. See [this guide](https://faun.pub/how-to-drop-and-delete-metrics-in-prometheus-7f5e6911fb33) for details. Disable the admin API after cleanup.
