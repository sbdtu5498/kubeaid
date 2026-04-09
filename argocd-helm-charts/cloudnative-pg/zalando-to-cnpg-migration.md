# Migrating PostgreSQL: Zalando Operator to CloudNativePG (CNPG)

Guide for migrating the SonarQube PostgreSQL database from the
[Zalando Postgres Operator](https://github.com/zalando/postgres-operator)
to [CloudNativePG](https://cloudnative-pg.io/) with zero data loss.

**Estimated downtime**: ~10-15 minutes
**Risk level**: Low (dump/restore of a single database, rollback always available)

## Why migrate?

- CNPG is the CNCF-adopted standard, actively developed
- Unified operator across the cluster (Keycloak, OSV-Scanner already use CNPG)
- Better backup integration via barman-cloud plugin (physical + WAL archiving)
- Simpler architecture (no Patroni/Spilo overhead)
- Better Prometheus monitoring integration

## Architecture comparison

### Zalando

```text
Zalando Postgres Operator
  └── postgresql CR: <name>-pgsql
      ├── Pod: <name>-pgsql-0 (Spilo/Patroni + PG 14)
      ├── PVC: pgdata-<name>-pgsql-0
      ├── Service: <name>-pgsql (master, 5432)
      ├── Service: <name>-pgsql-repl (replica, 5432)
      ├── Secret: <user>.<name>-pgsql.credentials.postgresql.acid.zalan.do
      └── CronJob: logical-backup-<name>-pgsql
```

### CNPG

```text
CNPG Operator + Barman Cloud Plugin
  └── Cluster CR: <name>-pgsql
      ├── Pod: <name>-pgsql-1 (vanilla PG 17)
      ├── PVC: <name>-pgsql-1
      ├── Service: <name>-pgsql-rw (primary, 5432)
      ├── Service: <name>-pgsql-ro (read-only, 5432)
      ├── Service: <name>-pgsql-r  (any replica, 5432)
      ├── Secret: <name>-pgsql-app (auto-generated)
      ├── ObjectStore: <name>-pgsql-backups
      └── ScheduledBackup: <name>-pgsql
```

### Key differences

| Aspect | Zalando | CNPG |
|--------|---------|------|
| PG image | Spilo (Patroni + PG 14) | Vanilla PostgreSQL 17 |
| HA mechanism | Patroni | Built-in CNPG controller |
| Primary service | `<name>` | `<name>-rw` |
| Secret naming | `<user>.<name>.credentials...acid.zalan.do` | `<name>-app` |
| Secret keys | `username`, `password` | `username`, `password`, `dbname`, `host`, `port`, `uri`, `jdbc-uri` |
| Backup method | Logical (pg_dump to S3) | Physical (barman-cloud, WAL archiving) |
| Filesystem | Writable | `readOnlyRootFilesystem: true` (`/tmp` not writable, use `/run`) |
| Socket auth | `psql -U <user>` works | Peer auth: only `psql -U postgres` on socket; use `-h localhost` + `PGPASSWORD` for app user |

## Prerequisites

- CNPG operator installed and healthy
- Barman-cloud plugin running (if backups are enabled)
- S3 bucket accessible for backups
- CNPG Helm chart templates added to the SonarQube chart (see [Code changes](#code-changes))
- **PG version**: pg_dump from PG 14 restores into PG 17 without issues;
  no need to upgrade Zalando PG 14 first

## Migration overview

```text
Phase 1: Code changes (no downtime)
  └── Add CNPG templates, update values, make Zalando conditional

Phase 2: Deploy CNPG cluster (no downtime)
  ├── Selective ArgoCD sync: only Cluster + ObjectStore + ScheduledBackup
  ├── Verify CNPG cluster healthy, pod running, services created
  └── DO NOT sync StatefulSet or delete Zalando CR yet

Phase 3: Data migration (~5 min, downtime starts)
  ├── Scale down SonarQube to 0 replicas
  ├── Verify connectivity from Zalando pod to CNPG -rw service
  └── Direct pod-to-pod: pg_dump | psql over in-cluster network

Phase 4: Switchover (~5 min, downtime continues)
  ├── Sync remaining resources (JDBC config points to CNPG)
  ├── SonarQube pod restarts with new connection
  └── Downtime ends when SonarQube is accessible

Phase 5: Cleanup (no downtime)
  ├── Delete Zalando postgresql CR
  ├── Delete old PVC
  └── Verify CNPG backups working
```

## Code changes

### Add CNPG Cluster template

Create `templates/cnpg-cluster.yaml`:

```yaml
{{- if .Values.cnpg.enabled }}
{{- $cnpg := .Values.cnpg }}

apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: sonarqube-pgsql
  labels:
    velero.io/exclude-from-backup: "true"

spec:
  instances: {{ $cnpg.instances }}

  {{- with $cnpg.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}

  storage:
    size: {{ $cnpg.size }}
    {{- if $cnpg.storageClass }}
    storageClass: {{ $cnpg.storageClass }}
    {{- end }}

  {{- if $cnpg.backups.enabled }}
  plugins:
    - enabled: true
      isWALArchiver: true
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: sonarqube-pgsql-backups
        serverName: "revision-{{ $cnpg.revision }}"
  {{- end }}

  bootstrap:
    {{- if $cnpg.recover.enabled }}
    recovery: sonarqube-pgsql
    {{- else }}
    initdb:
      database: sonarqube
      owner: sonarqube
    {{- end }}

  {{- if $cnpg.recover.enabled }}
  externalClusters:
    - name: sonarqube-pgsql
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: sonarqube-pgsql-backups
          serverName: "revision-{{ $cnpg.recover.revision }}"
  {{- end }}

  monitoring:
    enablePodMonitor: {{ $cnpg.backups.enabled }}
{{- end }}
```

### Add ObjectStore template

Create `templates/cnpg-object-store.yaml`:

```yaml
{{- if and .Values.cnpg.enabled .Values.cnpg.backups.enabled }}
{{- $backups := .Values.cnpg.backups }}

apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: sonarqube-pgsql-backups

spec:
  configuration:
    {{- if $backups.endpointURL }}
    endpointURL: {{ $backups.endpointURL }}
    {{- end }}
    destinationPath: {{ required ".destinationPath must be provided" $backups.destinationPath }}
    {{- if eq $backups.provider "aws" }}
    s3Credentials:
      {{- if $backups.aws.enableKube2IAMIntegration }}
      inheritFromIAMRole: true
      {{- else }}
      accessKeyId:
        name: sonarqube-pgsql-backup-creds
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: sonarqube-pgsql-backup-creds
        key: ACCESS_SECRET_KEY
      {{- end }}
    {{- end }}

    wal:
      compression: gzip
      encryption: AES256
      maxParallel: 8

  retentionPolicy: {{ $backups.retentionPolicy }}
{{- end }}
```

### Add ScheduledBackup template

Create `templates/cnpg-scheduled-backup.yaml`:

```yaml
{{- if and .Values.cnpg.enabled .Values.cnpg.backups.enabled }}
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: sonarqube-pgsql

spec:
  cluster:
    name: sonarqube-pgsql

  backupOwnerReference: self
  schedule: {{ .Values.cnpg.backups.schedule }}
  immediate: true

  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
{{- end }}
```

### Make Zalando template conditional

Wrap the existing `templates/postgres.yaml`:

```yaml
{{- if not .Values.cnpg.enabled }}
...existing Zalando postgresql CR...
{{- end }}
```

### Update values.yaml

Add CNPG defaults:

```yaml
cnpg:
  enabled: false
  revision: 0
  instances: 1
  size: 8Gi

  resources:
    requests:
      cpu: 100m
      memory: 500Mi
    limits:
      memory: 800Mi

  recover:
    enabled: false
    revision: 0

  backups:
    enabled: true
    schedule: "0 0 0 * * *"
    retentionPolicy: 30d
    provider: aws
    aws:
      enableKube2IAMIntegration: true
```

### JDBC connection changes

| Setting | Zalando (old) | CNPG (new) |
|---------|---------------|------------|
| `jdbcSecretName` | `sonarqube.sonarqube-pgsql.credentials.postgresql.acid.zalan.do` | `sonarqube-pgsql-app` |
| `jdbcUrl` | `jdbc:postgresql://sonarqube-pgsql/sonarqube?socketTimeout=1500` | `jdbc:postgresql://sonarqube-pgsql-rw/sonarqube?socketTimeout=1500` |
| `jdbcSecretPasswordKey` | `password` | `password` |
| `jdbcUsername` | `sonarqube` | `sonarqube` |

### Config repo values example

```yaml
sonarqube:
  jdbcOverwrite:
    enabled: true
    jdbcSecretName: sonarqube-pgsql-app
    jdbcSecretPasswordKey: password
    jdbcUrl: "jdbc:postgresql://sonarqube-pgsql-rw/sonarqube?socketTimeout=1500"
    jdbcUsername: sonarqube

cnpg:
  enabled: true
  instances: 1
  size: 8Gi
  backups:
    enabled: true
    provider: "aws"
    destinationPath: s3://<BUCKET>/cnpg/sonarqube
```

## Step-by-step execution

### Step 1: Deploy CNPG cluster (no downtime)

Push code changes, then in ArgoCD:

1. Open the SonarQube application
2. Click **Sync** → uncheck "All"
3. Check **only**: `Cluster/sonarqube-pgsql`, `ObjectStore`, `ScheduledBackup`
4. Click **Synchronize**
5. **Do NOT** sync the StatefulSet, ConfigMap, or delete Zalando CR yet

Verify:

```shell
# CNPG cluster healthy
kubectl get clusters.postgresql.cnpg.io sonarqube-pgsql -n sonarqube
# Expected: STATUS = "Cluster in healthy state"

# CNPG pod running
kubectl get pods -n sonarqube -l cnpg.io/cluster=sonarqube-pgsql
# Expected: sonarqube-pgsql-1  1/1  Running

# CNPG services created
kubectl get svc -n sonarqube | grep pgsql
# Expected: sonarqube-pgsql-rw, sonarqube-pgsql-ro, sonarqube-pgsql-r

# CNPG secret created
kubectl get secret sonarqube-pgsql-app -n sonarqube
```

### Step 2: Data migration (downtime starts)

```shell
# Scale down SonarQube to prevent writes
kubectl scale statefulset sonarqube-sonarqube -n sonarqube --replicas=0
kubectl wait --for=delete pod/sonarqube-sonarqube-0 -n sonarqube --timeout=120s

# Record baseline from source
kubectl exec -n sonarqube sonarqube-pgsql-0 -- \
  psql -U sonarqube -d sonarqube -c "
  SELECT pg_size_pretty(pg_database_size('sonarqube'));
  SELECT count(*) FROM information_schema.tables WHERE table_schema='public';
  SELECT 'projects' as tbl, count(*) FROM projects
  UNION ALL SELECT 'users', count(*) FROM users
  UNION ALL SELECT 'issues', count(*) FROM issues
  UNION ALL SELECT 'rules', count(*) FROM rules
  UNION ALL SELECT 'components', count(*) FROM components;"

# Get CNPG password
CNPG_PASS=$(kubectl get secret sonarqube-pgsql-app -n sonarqube \
  -o jsonpath='{.data.password}' | base64 -d)

# Verify connectivity from Zalando pod to CNPG
kubectl exec -n sonarqube sonarqube-pgsql-0 -- \
  bash -c "PGPASSWORD='${CNPG_PASS}' psql \
    -h sonarqube-pgsql-rw.sonarqube.svc \
    -U sonarqube -d sonarqube -c 'SELECT 1'"

# Direct pod-to-pod migration
# IMPORTANT: Use "export PGPASSWORD" so the password is available to BOTH
# pg_dump (local) and psql (remote) sides of the pipeline.
kubectl exec -n sonarqube sonarqube-pgsql-0 -- \
  bash -c "export PGPASSWORD='${CNPG_PASS}' && \
    pg_dump -U sonarqube -d sonarqube --clean --if-exists | \
    psql -h sonarqube-pgsql-rw.sonarqube.svc -U sonarqube -d sonarqube"
# Wait for exit code 0. Spilo-specific warnings are expected and safe.

# Verify data integrity on CNPG
kubectl exec -n sonarqube sonarqube-pgsql-1 -c postgres -- \
  psql -U postgres -d sonarqube -c "
  SELECT pg_size_pretty(pg_database_size('sonarqube'));
  SELECT count(*) as table_count
    FROM information_schema.tables WHERE table_schema = 'public';
  SELECT 'projects' as tbl, count(*) FROM projects
  UNION ALL SELECT 'users', count(*) FROM users
  UNION ALL SELECT 'issues', count(*) FROM issues
  UNION ALL SELECT 'rules', count(*) FROM rules
  UNION ALL SELECT 'components', count(*) FROM components;"
# Row counts MUST match. Table count may be ~4 less (Spilo extension views).
# DB size ±10% is normal.
```

### Step 3: Switchover (downtime continues)

Sync the remaining resources in ArgoCD (StatefulSet, ConfigMaps). This updates
the JDBC connection to point to CNPG:

```shell
# Verify SonarQube pod starts
kubectl get pods -n sonarqube -l app=sonarqube -w
# Wait for: sonarqube-sonarqube-0  1/1  Running

# Check logs for successful DB connection
kubectl logs -n sonarqube sonarqube-sonarqube-0 --tail=50
# Look for: "SonarQube is operational"
# Should NOT see: "Cannot connect to database"

# Verify via API
curl -s https://<SONARQUBE_URL>/api/system/status
# Expected: {"status":"UP"}
```

### Step 4: Post-migration validation


Sonarqube pod logs will have a message like

```
The Database needs to be manually upgraded
```
When you see this, you can go to the url where Sonarqube is deployed, and that will redirect you to `https://sonarqube.yourdomain.com/maintenance`.
You will need to go to `https://sonarqube.yourdomain.com/setup` to **Manually** approve the DB upgrade. Without this
critical step, Sonarqube will be stuck in maintenace mode.


> NOTE: If you are upgrading to Postgres 18, that is not supported by the current sonarqube version used at the time of writing this guide. There is a good chance that the operator will spin up pgsql 18 if you don't specify it explicitly in the `kind: Cluster` manifest for sonarqube-pgsql.

After the DB upgrade is completed, the sonarqube pod logs will show the completion status and then Sonarqube ingress should be up.

```shell
# CNPG cluster healthy
kubectl get clusters.postgresql.cnpg.io sonarqube-pgsql -n sonarqube

# First backup completed
kubectl get backups.postgresql.cnpg.io -n sonarqube

# WAL archiving working
kubectl exec -n sonarqube sonarqube-pgsql-1 -c postgres -- \
  psql -U postgres -d sonarqube -c "SELECT * FROM pg_stat_archiver;"

# Active connections from SonarQube
kubectl exec -n sonarqube sonarqube-pgsql-1 -c postgres -- \
  psql -U postgres -d sonarqube -c \
  "SELECT client_addr, usename, datname, state FROM pg_stat_activity WHERE datname='sonarqube';"
```

**Checklist**:

- [ ] SonarQube UI accessible, login works
- [ ] All projects visible with history
- [ ] Quality gates intact
- [ ] Row counts match source
- [ ] CNPG cluster healthy
- [ ] First backup completed
- [ ] WAL archiving active
- [ ] No DB errors in SonarQube logs

### Step 5: Cleanup (wait 24-48h after validation)

```shell
# Zalando CR removed (via ArgoCD sync or manual)
kubectl get postgresql sonarqube-pgsql -n sonarqube
# Expected: not found

# Delete old PVC (only after confirming CNPG works AND backups run)
kubectl delete pvc pgdata-sonarqube-pgsql-0 -n sonarqube
```

## Rollback plan

### During data migration (before switchover)

SonarQube is still pointed at Zalando. Simply scale it back up:

```shell
kubectl scale statefulset sonarqube-sonarqube -n sonarqube --replicas=1
```

### After switchover

1. Revert JDBC config to point back to Zalando service
2. Sync ArgoCD
3. Delete SonarQube pod to force reconnection

The Zalando database remains running until you explicitly delete the
`postgresql` CR, so rollback is always safe.

## Approaches that do NOT work

> **Do NOT use `kubectl cp` or `kubectl exec -- cat` for database dump files.**

These methods silently truncate binary data due to WebSocket limitations:

| Method | Result | Issue |
|--------|--------|-------|
| `kubectl cp` | 5.4 MB → 704 KB | Silent truncation via tar-over-WebSocket |
| `kubectl exec -- cat > file` | 5.4 MB → 1.2 MB | WebSocket buffering drops data |
| Dual `kubectl exec` pipe | 5.4 MB → 1.8 MB | Double WebSocket pass |

The **only reliable method** is direct pod-to-pod `pg_dump | psql` over the
internal Kubernetes network. The SQL stream stays within the cluster and
never passes through WebSocket binary transfer.

## FAQ

### Will there be data loss?

No. `pg_dump` is run while the application is scaled to 0 replicas (no writes).
Row counts are verified before and after. The direct pod-to-pod pipe is reliable.

### What about the PG version difference (14 vs 17)?

`pg_dump` from PG 14 produces standard SQL that PG 17 accepts without issues.
PostgreSQL guarantees forward compatibility of dump formats. No need to upgrade
Zalando to PG 17 first.

### Why `export PGPASSWORD` instead of inline?

In a bash pipeline `PGPASSWORD='xxx' pg_dump ... | psql ...`, the variable is
only set for `pg_dump` (left side), not `psql` (right side). Using
`export PGPASSWORD='xxx' &&` makes it available to both.

### Table count differs after migration?

Expected. Zalando creates ~4 Spilo extension views (`pg_stat_kcache`,
`pg_stat_kcache_detail`, `pg_stat_statements`, `pg_stat_statements_info`) that
are not application data and won't exist in CNPG. What matters is that
application table **row counts match exactly**.

### How to connect to CNPG pod as the app user?

CNPG uses peer auth on Unix sockets (only `psql -U postgres` works on socket).
For the app user, use TCP:

```shell
PGPASSWORD='<password>' psql -h localhost -U sonarqube -d sonarqube
```

### `pg_dump` or `psql` shows Spilo-specific warnings?

Safe to ignore. These are about Zalando monitoring helpers:

- `role "admin" does not exist`
- `extension "pg_stat_kcache" is not available`
- `schema "metric_helpers" / "user_management"` errors

SonarQube does not use any of these.

### How to verify CNPG backups?

```shell
kubectl get scheduledbackups.postgresql.cnpg.io -n sonarqube
kubectl get backups.postgresql.cnpg.io -n sonarqube
kubectl exec -n sonarqube sonarqube-pgsql-1 -c postgres -- \
  psql -U postgres -d sonarqube -c "SELECT * FROM pg_stat_archiver;"
```

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/current/)
- [CNPG Backup and Recovery](https://cloudnative-pg.io/documentation/current/backup/)
- [PostgreSQL pg_dump Documentation](https://www.postgresql.org/docs/current/app-pgdump.html)
- [SonarQube Database Requirements](https://docs.sonarsource.com/sonarqube-server/latest/setup-and-upgrade/install-the-server/installing-the-database/)
