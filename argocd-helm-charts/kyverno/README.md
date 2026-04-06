# Kyverno Chart: Harbor Proxy-Cache Policy

This chart ships Kyverno policies for redirecting container images through Harbor
proxy-cache projects (e.g., Docker Hub, GHCR, and registry.k8s.io). It also
includes a small `.kyverno-test` suite for local validation.

## Local policy testing (.kyverno-test)

Prerequisites:
- `helm`
- `kyverno` CLI (v1.11+)

Install Kyverno CLI:

```bash
# macOS (Homebrew)
brew install kyverno

# Linux (x86_64)
curl -sL https://github.com/kyverno/kyverno/releases/latest/download/kyverno-cli_linux_x86_64.tar.gz \
| tar -xz -C /usr/local/bin kyverno

# Verify
kyverno version
```

Docs: https://kyverno.io/docs/kyverno-cli/

From the repo root:

```bash
# Render the policy used by the test harness
helm template kyverno argocd-helm-charts/kyverno \
  -f <values-file>.yaml \
  --show-only templates/harbor-proxy-cache/harbor-proxy-cache-mutate.yaml \
  > argocd-helm-charts/kyverno/templates/harbor-proxy-cache/.kyverno-test/policy.yaml

# Run the tests
kyverno test argocd-helm-charts/kyverno/templates/harbor-proxy-cache/.kyverno-test
```

Notes:
- The test data lives in `templates/harbor-proxy-cache/.kyverno-test/`.
- If tests fail after a policy update, re-render `policy.yaml` using the command
  above and re-run `kyverno test`.

## Render and apply to a cluster

```bash
helm template kyverno argocd-helm-charts/kyverno \
  -f <values-file>.yaml \
  --show-only templates/harbor-proxy-cache/harbor-proxy-cache-mutate.yaml \
| kubectl apply -f -
```

Use a cluster-specific values file that sets the Harbor registry, project names,
and imagePullSecret names. Example keys:

- `harborProxyCache.registry`
- `harborProxyCache.dockerHubProject`
- `harborProxyCache.ghcrProject`
- `harborProxyCache.k8sProject`
- `harborProxyCache.imagePullSecretName`
- `harborProxyCache.ghcrImagePullSecretName`
- `harborProxyCache.k8sImagePullSecretName`

## Notes

- **Registry names with dots**: the implicit Docker Hub regex excludes registries
  which include a dot in the hostname (e.g., `ghcr.io`, `quay.io`,
  `registry.k8s.io`). Those are handled by explicit registry blocks.

## Troubleshooting

- If images are not mutated, check the `ClusterPolicy` and `PolicyReport` output.
- If pulls fail with `401`, confirm the Harbor robot account has `pull` access
  to the matching proxy-cache project and the correct imagePullSecret exists
  in the namespace.
