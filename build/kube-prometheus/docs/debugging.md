# Debugging & Testing

## Jsonnet debugging

Dump an object to stderr using [`std.trace`](https://jsonnet.org/ref/stdlib.html#trace):

```jsonnet
dashboards+: std.trace(std.toString(CephMixin), CephMixin.grafanaDashboards),
```

Output an object to a file by adding a line at the bottom of the return value in `common-template.jsonnet`:

```jsonnet
+ { debug: mixins }
```

## Running the tests

### Lint — static vars access check

Checks that every `vars.field` access in `common-template.jsonnet` is either defaulted, guarded, or validated. Silent on success, prints errors on failure.

```sh
cd build/kube-prometheus
bash tests/lint_vars_access.sh
```

### Unit tests

Run against all available library versions:

```sh
cd build/kube-prometheus
for version in libraries/*/; do
  echo "Testing against ${version}vendor"
  jsonnet -J "${version}vendor" tests/addmixin_test.jsonnet
  jsonnet -J "${version}vendor" tests/validate_vars_test.jsonnet
done
```

### E2E compilation tests

Runs `build.sh` against every fixture in `e2e/vars/<version>/` and reports pass/fail:

```sh
cd build/kube-prometheus
bash e2e/run.sh
```

Fixtures are organised by kube-prometheus version:

```
e2e/vars/
  v0.13.0/  kubeadm-minimal
  v0.16.0/  aks-minimal, kubeadm-minimal, kubeadm-with-keycloak, kops-minimal, kops-with-opensearch
  v0.17.0/  aks-minimal, kubeadm-minimal, kubeadm-with-keycloak, kops-minimal, kops-with-opensearch
```

## CI

All tests run automatically on every PR via `.gitea/workflows/promtool.yaml`:

1. `promtool test rules` — Prometheus rule unit tests
2. `mixtool lint` — mixin linting
3. Jsonnet unit tests (lint + addmixin + validate, against all library versions)
4. E2E compilation tests
