# vuls-dictionary

Helm chart for deploying Vuls vulnerability scanning infrastructure: CVE dictionary fetcher, dictionary server, PostgreSQL storage, and the Vuls scan server.

## Architecture

**Important:** In vuls v0.38.6+, vuls2 detection is **always active** — the legacy OVAL-only scan path has been removed upstream. The `[vuls2]` config section is always included in config.toml to ensure `SkipUpdate = true` and the correct db path. The CVE dictionary is still used for enrichment (CVSS scores, advisory details) but not for primary vulnerability detection.

The `vuls2.enabled` flag controls only whether init containers pre-fetch the vuls-nightly-db. Scan results are written to `/vuls/results/`.

## Components

| Component | Description |
|-----------|-------------|
| **CVE dictionary** | CronJob fetching CVE data (NVD) via [go-cve-dictionary](https://github.com/vulsio/go-cve-dictionary) |
| **Dictionary server** | HTTP server exposing CVE (port 1323) data to Vuls for enrichment |
| **CVE seed job** | One-time Job to bootstrap initial CVE data (runs once, not a Helm hook) |
| **PostgreSQL** | CNPG cluster (`pgsql-cve`) storing CVE dictionary data |
| **vuls2 init containers** | Fetch and decompress the vuls-nightly-db (~7GB) into the results PVC |
| **Vuls server** | Scan server (port 5515) that accepts package lists and returns vulnerability results |
| **Vuls exporter** | Sidecar that reads scan results and pushes them to the Obmondo API via mTLS |

## Quick start

```yaml
# values.yaml
schedule: "0 2 1,15 * *"

cve:
  enabled: true
  fetchDB:
    - nvd
  yearsFrom: 2022

# Controls db pre-fetching only; vuls2 detection is always active in v0.38.6+
vuls2:
  enabled: true

vulsServer:
  enabled: true

postgresql:
  instances: 1
  size: 5Gi
```

## Configuration

### Global

| Parameter | Description | Default |
|-----------|-------------|---------|
| `schedule` | Cron schedule for CVE dictionary fetches | `"0 2 1,15 * *"` |

### CVE dictionary

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cve.enabled` | Enable CVE dictionary fetching | `true` |
| `cve.fetchDB` | List of CVE sources to fetch | `[nvd]` |
| `cve.yearsFrom` | Fetch CVEs starting from this year up to current year | `2022` |
| `cve.resources` | Resource requests/limits for CVE fetch containers | 100m CPU, 256Mi/1Gi |
| `image.cve.repository` | CVE dictionary image | `vuls/go-cve-dictionary` |
| `image.cve.tag` | CVE dictionary image tag | `v0.16.0` |

### vuls2

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vuls2.enabled` | Pre-fetch vuls2 nightly db via init containers (vuls2 detection is always active in v0.38.6+) | `true` |
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
| `vulsServer.resultsStorage.size` | PVC size for scan results | `15Gi` |
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

### PostgreSQL

A CNPG cluster is created for CVE dictionary data.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.instances` | Number of CNPG instances per cluster | `1` |
| `postgresql.size` | PVC size per instance | `5Gi` |
| `postgresql.storageClass` | Storage class (empty = default) | `""` |
| `postgresql.resources` | Resource requests/limits | 100m CPU, 256Mi/512Mi |
| `postgresql.backups.enabled` | Enable backups | `false` |

### CronJob behavior

CronJobs use `concurrencyPolicy: Forbid` to prevent overlapping runs, and retain the last 3 successful and 3 failed jobs for debugging.

## Client

Linux hosts run [obmondo-security-exporter](https://github.com/Obmondo/security-exporter), a Prometheus exporter that collects installed packages, sends them to the Vuls server for scanning, and exposes CVE metrics. It can run as a daemon with scheduled scans or as a one-shot CLI tool.
