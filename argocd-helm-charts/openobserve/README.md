# OpenObserve Installation Guide

> **Tip:** Before installing OpenObserve, you must deploy the **OpenTelemetry Collector**.  
> Add it as a regular Argo CD application in your `kubeaid-config` repository.

---

## Create Sealed Secrets for PostgreSQL

```sh
kubectl create secret generic openobserve-pg-credentials \
  --namespace openobserve \
  --from-literal=LOGICAL_BACKUP_AZURE_STORAGE_ACCOUNT_KEY="<azure-storage-account-key>" \
  --from-literal=username="openobserve" \
  --from-literal=password="Batman123" \
  --dry-run=client -o yaml | kubeseal --controller-namespace system \
  --controller-name sealed-secrets-controller \
  -o yaml > k8s/my-cluster/sealed-secrets/openobserve/openobserve-pg-credentials.yaml
```

The resulting file `openobserve-pg-credentials.yaml` is now a sealed secret ready for Argo CD.

## Define the OpenObserve Credentials Template

Save the following as openobserve-credentials.yaml (inside the same sealed-secrets folder).

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  creationTimestamp: null
  name: openobserve-credentials
  namespace: openobserve
spec:
  encryptedData: {}
  template:
    data:
      dexConfig: |
        issuer: https://dex.your-cluster-ingress.com/dex
        storage:
          type: kubernetes
          config:
            inCluster: true
        web:
          http: 0.0.0.0:5556
        frontend:
          issuer: "OpenObserve"
          logoURL: "https://cloud.openobserve.ai/web/src/assets/images/common/open_observe_logo.svg"
        expiry:
          idTokens: 10m
          refreshTokens:
            validIfNotUsedFor: 30m
        staticClients:
          - id: internalclient
            name: internalclient
            secret: {{ index . "O2_DEX_CLIENT_SECRET" }}
            redirectURIs:
              - https://openobserve.your-cluster-ingress.com/config/redirect
        oauth2:
          responseTypes:
            - code
          skipApprovalScreen: true
        logger:
          level: "debug"
        connectors:
          - type: oidc
            id: openobserve
            name: openobserve
            config:
              issuer: https://keycloak.your-cluster-ingress.com/auth/realms/Kilroy
              clientID: openobserve
              clientSecret: {{ index . "DEX_CONNECTOR_CLIENT_SECRET" }}
              redirectURI: https://dex.your-cluster-ingress.com/dex/callback
              scopes: ["openid", "profile", "email", "groups", "offline_access"]
              getUserInfo: true
              claimMapping:
                email: email
                name: name
```

## Populate the Credentials Sealed Secret

> NOTE: Some secret values can only be populated once the initial Openobserve setup is complete.
> In that case, you need to merge those secret values in sealed secrets again. Learn more about [Sealed Secrets](https://github.com/Obmondo/KubeAid/tree/master/argocd-helm-charts/sealed-secrets).

Run the command below to inject the real values and seal the secret.

```sh
kubectl create secret generic openobserve-credentials \
  --namespace openobserve \
  --from-literal=ZO_ROOT_USER_EMAIL="root@example.com" \
  --from-literal=ZO_ROOT_USER_PASSWORD="Complexpass#123" \
  --from-literal=AZURE_STORAGE_ACCOUNT_KEY="<azure-storage-account-key>" \
  --from-literal=AZURE_STORAGE_ACCOUNT_NAME="<azure-storage-account-name>" \
  --from-literal=ZO_META_POSTGRES_DSN="postgres://openobserve:Batman123@openobserve-postgres-rw.openobserve:5432/app" \
  --from-literal=OPENFGA_DATASTORE_URI="postgres://openobserve:Batman123@openobserve-postgres-rw.openobserve:5432/app" \
  --from-literal=ZO_TRACING_HEADER_KEY="Authorization" \
  --from-literal=ZO_TRACING_HEADER_VALUE="Basic <opentelemtry-token-from-openobserve-data-sources>" \
  --from-literal=ZO_SMTP_USER_NAME="ABAAQQQQFFFFF" \
  --from-literal=ZO_SMTP_PASSWORD="+fjlahsguykevfkajvjk#jsbj43" \
  --from-literal=O2_DEX_CLIENT_SECRET="<base64-of-dex-client-secret>" \
  --from-literal=DEX_CONNECTOR_CLIENT_SECRET="<dex-client-secret>" \
  --from-literal=OPENOBSERVE_AUTH_TOKEN="Basic <opentelemtry-token-from-openobserve-data-sources>" \
  --from-literal=OPENOBSERVE__K8S_EVENTS_AUTH_TOKEN="Basic <opentelemtry-token-from-openobserve-data-sources>" \
  --dry-run=client -o yaml | kubeseal --controller-namespace system \
  --controller-name sealed-secrets-controller \
  -o yaml --merge-into k8s/my-cluster/sealed-secrets/openobserve/openobserve-credentials.yaml
```

### Quick reference of the keys you just set

| Key | Example value/info |
| :--- | :--- |
| `ZO_ROOT_USER_EMAIL` | `root@example.com` |
| `ZO_ROOT_USER_PASSWORD` | `Complexpass#123` |
| `AZURE_STORAGE_ACCOUNT_KEY` | `<azure-storage-key>` |
| `AZURE_STORAGE_ACCOUNT_NAME` | `openobservestorage` |
| `ZO_META_POSTGRES_DSN` | `postgres://openobserve:Batman123@openobserve-postgres-rw.openobserve:5432/app` |
| `OPENFGA_DATASTORE_URI` | same as above |
| `ZO_TRACING_HEADER_KEY` | `Authorization` |
| `ZO_TRACING_HEADER_VALUE` | `Basic <opentelemtry-token-from-openobserve-data-sources>` |
| `ZO_SMTP_USER_NAME` | `ABAAQQQQFFFFF` |
| `ZO_SMTP_PASSWORD` | `+fjlahsguykevfkajvjk#jsbj43` |
| `O2_DEX_CLIENT_SECRET` | `<base64-of-dex-client-secret>` |
| `DEX_CONNECTOR_CLIENT_SECRET` | `<dex-client-secret>` obtained after setting up keycloak for dex |
| `OPENOBSERVE_AUTH_TOKEN` | `Basic <opentelemtry-token-from-openobserve-data-sources>` obtained after O2 is setup. O2 Dashboard -> Data Sources -> Opentelemetry |
| `OPENOBSERVE__K8S_EVENTS_AUTH_TOKEN` | same as above |

*All commands assume you have `kubectl`, `kubeseal` installed.
Ensure you've access to the `system` namespace where the sealed-secrets controller runs.*

## Troubleshooting

### User deletion

If a user logged in with `user` role, we need to remove the user, update the dex config to enable viewer role for new users.
However, in order to do that, the added user needs to be removed, and then add back via login.
But the UI doesn't give any option to delete the user account. Hence, we need to do that via curl request.

```sh
curl -X 'DELETE' \
  'https:///openobserve.your-cluster-ingress.com/api/default/users/<user-email-to-remove>' \
  -u '<root-user-email>:<root-user-password>' \
  -H 'accept: application/json'
```

## Extras
- [A short explanation on how Open Observe manages memory](https://github.com/openobserve/openobserve/discussions/2711)

