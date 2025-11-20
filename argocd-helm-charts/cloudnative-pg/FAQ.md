# FAQ - CloudNativePG / PostgreSQL

## pg_dump / logical-backup fails with `ERROR: out of shared memory`

### Symptoms
While running a logical backup (e.g., `postgres-logical-backup` job), the backup fails  
with errors similar to:  
```
pg_dump: error: query failed: ERROR:  out of shared memory
HINT:  You might need to increase "max_locks_per_transaction".
pg_dumpall: error: pg_dump failed on database "<db_name>", exiting
```
The logs may also show extremely long `LOCK TABLE ...` statements when many partitions  
or child tables exist.  

### Cause
PostgreSQL uses a shared lock table whose size is controlled by the parameter:  
```
max_locks_per_transaction
```
This parameter determines how many distinct objects (tables, partitions, indexes, etc.) a single  
backend can lock on average.  
If a database has **hundreds or thousands of partitions**, utilities such as `pg_dump` can  
temporarily require more locks than the default 64.  

As a result, logical backups can fail with `out of shared memory`.

### Temporary Fix

The logical backup was failing with `ERROR: out of shared memory`, caused by the default value of:
```
kubectl exec -it <pod> -n <namespace> -- \
  psql -U postgres -c "SHOW max_locks_per_transaction;"

 max_locks_per_transaction
---------------------------
 64
(1 row)
```
A temporary increase to **128** allowed `pg_dump` to complete successfully.  
This was done by locating the `postgresql` kind and editing the relevant **YAML object** to add  
the `max_locks_per_transaction` parameter with the new value, as shown in the permanent fix.  

### Permanent Fix

This parameter must be configured in the PostgreSQL cluster manifest (CloudNativePG/Zalando)  
so the change is applied permanently.  

Example CR configuration:  

```yaml
  Postgresql:
    Parameters:
      max_locks_per_transaction:  128
```
