# vuls-dictionary

Helm chart for deploying Vuls vulnerability scanning infrastructure: CVE and OVAL dictionary fetchers, dictionary servers, PostgreSQL storage, and the Vuls scan server.

## Components

| Component | Description |
|-----------|-------------|
| **CVE dictionary** | CronJob fetching CVE data (NVD, MITRE, JVN, Fortinet) via [go-cve-dictionary](https://github.com/vulsio/go-cve-dictionary) |
| **OVAL dictionary** | CronJobs fetching OVAL data per distro via [goval-dictionary](https://github.com/vulsio/goval-dictionary) |
| **Dictionary servers** | HTTP servers exposing CVE (port 1323) and OVAL (port 1324) data to Vuls |
| **Vuls server** | Scan server (port 5515) that accepts package lists and returns vulnerability results |
| **PostgreSQL** | CNPG-managed cluster storing all dictionary data |

## Quick start

```yaml
# values.yaml
schedule: "0 2 * * *"

cve:
  enabled: true
  fetchDB:
    - nvd
    - mitre

oval:
  enabled: true
  fetchDB:
    debian:
      - "12"
    ubuntu:
      - "24.04"

vulsServer:
  enabled: true

postgresql:
  instances: 2
  size: 5Gi
```

## Configuration

### Global

| Parameter | Description | Default |
|-----------|-------------|---------|
| `schedule` | Cron schedule for dictionary fetches | `"0 2 * * *"` |
| `scheduleSpreadMinutes` | Minutes between OVAL CronJob schedules to spread load | `5` |

### CVE dictionary

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cve.enabled` | Enable CVE dictionary fetching | `true` |
| `cve.fetchDB` | List of CVE sources to fetch | `[nvd, mitre, jvn, fortinet]` |
| `cve.resources` | Resource requests/limits for CVE fetch containers | 100m/1 CPU, 256Mi/1Gi |
| `image.cve.repository` | CVE dictionary image | `vuls/go-cve-dictionary` |
| `image.cve.tag` | CVE dictionary image tag | `v0.16.0` |

### OVAL dictionary

| Parameter | Description | Default |
|-----------|-------------|---------|
| `oval.enabled` | Enable OVAL dictionary fetching | `true` |
| `oval.fetchDB` | Map of distro to version list | See `values.yaml` |
| `image.oval.repository` | OVAL dictionary image | `vuls/goval-dictionary` |
| `image.oval.tag` | OVAL dictionary image tag | `v0.15.1` |

Supported distros: `redhat`, `debian`, `ubuntu`, `sles-server`, `alpine`, `amazon`, `oracle`, `rocky`.

### Vuls server

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vulsServer.enabled` | Deploy the Vuls scan server | `true` |
| `vulsServer.image.repository` | Vuls server image | `vuls/vuls` |
| `vulsServer.image.tag` | Vuls server image tag | `v0.38.6` |
| `vulsServer.port` | Vuls server listen port | `5515` |
| `vulsServer.resources` | Resource requests/limits | 100m CPU, 256Mi/512Mi |
| `vulsServer.resultsStorage.size` | PVC size for scan results | `2Gi` |
| `vulsServer.resultsStorage.accessMode` | PVC access mode | `ReadWriteOnce` |

### PostgreSQL

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.instances` | Number of CNPG instances | `2` |
| `postgresql.size` | PVC size per instance | `5Gi` |
| `postgresql.storageClass` | Storage class (empty = default) | `""` |
| `postgresql.backups.enabled` | Enable backups | `false` |

### CronJob behavior

All CronJobs use `concurrencyPolicy: Forbid` to prevent overlapping runs, and retain the last 3 successful and 3 failed jobs for debugging.

## Client

Linux hosts run [obmondo-security-exporter](https://github.com/Obmondo/security-exporter), a Prometheus exporter that collects installed packages, sends them to the Vuls server for scanning, and exposes CVE metrics. It can run as a daemon with scheduled scans or as a one-shot CLI tool.
