# KubeAid-addons

A Helm chart for provisioning namespace-scoped infrastructure — network policies, database instances, and other common components. A single deployment per namespace, fully controlled by values.yaml.

## Overview

`kubeaid-addons` is deployed **once per namespace** and is driven entirely by the `values.yaml` of the application helm chart. What you put in your values file determines what gets rendered — network policies, database instances, and other common infrastructure components.

KubeAid-addons is a  companion Helm chart that provides shared infrastructure components to support your application charts — such as network policies, database instances, and other common primitives. Instead of managing multiple dependency charts, everything lives here. You control what's enabled configuration blocks in your values.

## Usage

Create one ArgoCD Application per namespace:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubeaid-addons-mattermost
spec:
  source:
    repoURL: https://github.com/your-org/kubeaid-helm-charts
    path: kubeaid-addons
    helm:
      valueFiles:
        - values/mattermost.yaml
  destination:
    namespace: mattermost
```

## Values

### Network Policies

Enable/disable netpols in your kubeaid-config repo:

```yaml
<application-name>:
    ciliumNetworkPolicy:
        enabled: true
```


### Excluding applications from default deny

If certain pods in the namespace should be excluded from the default deny policy (e.g. agents, exporters, or other system-level workloads that need unrestricted access), add them under `defaultDeny.excludedPods` using their label selectors in your kubeaid-config repo.

```yaml
ciliumNetworkPolicy:
  defaultDeny:
    excludedPods:
      - app: teleport-kube-agent
      - app.kubernetes.io/instance: obmondo-k8s-agent
      - app: gitea-stats-exporter
      - app.kubernetes.io/instance: gitea-stats-exporter
```

### CNPG PostgreSQL Network Policy

Each CNPG PostgreSQL instance can have its own Cilium network policy to control ingress and egress traffic. Enable it under your postgres values in your kubeaid-config repo:

```yaml
postgres:
  mattermost-postgres:
    netpol: true
```

By default the policy allows:

- **Egress** to `kube-apiserver` on ports `443`/`6443`
- **Egress** between PostgreSQL pods for cluster replication
- **Ingress** between PostgreSQL pods for cluster replication

#### Allowing client applications

To allow specific application pods to connect to PostgreSQL, add them under `clients`:
```yaml
postgres:
  <application-name>:
    clients:
      - labels:
          <label-key>: <label-value>
```
