# vuls-dictionary

Helm chart for deploying the Vuls vulnerability scan server backed by the [vuls2 unified database](https://github.com/future-architect/vuls).

## Architecture

This chart uses **vuls2** as the sole vulnerability detection engine. The legacy go-cve-dictionary / PostgreSQL pipeline has been removed — vuls2's nightly SQLite database contains all CVE, advisory, and detection data in a single file.

The vuls-nightly-db (~7 GB uncompressed) is fetched once via init containers and cached on a PVC. The vuls server reads it at startup with `SkipUpdate = true` so no outbound network access is needed at scan time.

### How it works

1. **Init containers** pull and decompress `ghcr.io/vulsio/vuls-nightly-db` into `/vuls/vuls.db`
2. **Vuls server** starts on port 5515 with `config.toml` pointing at the local database
3. **Clients** (e.g. [obmondo-security-exporter](https://github.com/Obmondo/security-exporter)) POST package lists and receive CVE results

## Components

| Component | Description |
|-----------|-------------|
| **vuls2 init containers** | Fetch and decompress the vuls-nightly-db (~7GB) into the results PVC |
| **Vuls server** | Scan server (port 5515) that accepts package lists and returns vulnerability results |
| **Vuls exporter** | Optional sidecar that reads scan results and pushes them to the Obmondo API via mTLS |

## Quick start

```yaml
# values.yaml
vuls2:
  enabled: true

vulsServer:
  enabled: true
```

## Configuration

### vuls2

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vuls2.enabled` | Pre-fetch vuls2 nightly db via init containers | `true` |
| `vuls2.image.repository` | vuls2 nightly database OCI image | `ghcr.io/vulsio/vuls-nightly-db` |
| `vuls2.image.tag` | vuls2 database image tag | `"0"` |
| `vuls2.image.pullPolicy` | Image pull policy | `IfNotPresent` |

When enabled, two init containers run before the vuls-server starts:
1. **fetch-vuls2-db** — pulls the compressed database via `oras`
2. **decompress-vuls2-db** — decompresses with `zstd`

Both init containers skip work if a valid database (>5GB) already exists on the PVC.

### Vuls server

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vulsServer.enabled` | Deploy the Vuls scan server | `true` |
| `vulsServer.image.repository` | Vuls server image | `vuls/vuls` |
| `vulsServer.image.tag` | Vuls server image tag | `v0.38.6` |
| `vulsServer.port` | Vuls server listen port | `5515` |
| `vulsServer.resources` | Resource requests/limits | 50m/100m CPU, 256Mi/512Mi |
| `vulsServer.resultsStorage.size` | PVC size for scan results and vuls2 db | `15Gi` |
| `vulsServer.resultsStorage.accessMode` | PVC access mode | `ReadWriteOnce` |
| `vulsServer.resultsStorage.storageClass` | Storage class (empty = default) | `""` |

### Vuls exporter

The vuls-exporter runs as a sidecar in the vuls-server pod. It reads scan result JSON files and pushes them to the Obmondo API using mTLS client certificates.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vulsExporter.enabled` | Enable the exporter sidecar | `false` |
| `vulsExporter.image.repository` | Exporter image | `ghcr.io/obmondo/vuls-exporter` |
| `vulsExporter.image.tag` | Exporter image tag | `1.0.0-9bd9ca5` |
| `vulsExporter.obmondo.url` | Obmondo API URL | `""` |
| `vulsExporter.interval` | Push interval | `"12h"` |
| `vulsExporter.tls.secretName` | Kubernetes Secret containing TLS client certs | `""` |
| `vulsExporter.tls.certFile` | Path to client certificate inside the container | `/etc/ssl/vuls-exporter/tls.crt` |
| `vulsExporter.tls.keyFile` | Path to client key inside the container | `/etc/ssl/vuls-exporter/tls.key` |
| `vulsExporter.tls.caFile` | Path to CA certificate (optional, omitted if empty) | `""` |
| `vulsExporter.resources` | Resource requests/limits | 20m/50m CPU, 32Mi/64Mi |

The TLS secret should contain `tls.crt`, `tls.key`, and optionally `ca.crt` keys. When `tls.secretName` is empty, TLS is not configured.

## Client

Linux hosts run [obmondo-security-exporter](https://github.com/Obmondo/security-exporter), a Prometheus exporter that collects installed packages, sends them to the Vuls server for scanning, and exposes CVE metrics. It can run as a daemon with scheduled scans or as a one-shot CLI tool.
