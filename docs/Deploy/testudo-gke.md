# Testudo Srl Fleet deployment

This directory adds the Testudo infrastructure separately from Fleet upstream
application code. The deployment target is GKE Autopilot cluster `tst-kube` in
project `testudo-dev`, region `europe-west1`, namespace `fleet`.

## Pinned components

- Fleet `fleetdm/fleet:v4.90.1` (current release on 2026-08-15)
- MySQL `mysql:8.0.44` with InnoDB (Fleet 4.90.1 requires MySQL 8.0.44+)
- Redis `redis:7.4.5-alpine` with authentication and no persistence
- BusyBox `busybox:1.37.0`
- Google Cloud CLI `gcr.io/google.com/cloudsdktool/google-cloud-cli:578.0.0-slim`

Fleet uses Redis for queues and reconstructible cache data, so Redis has no
PVC. MySQL is a one-replica StatefulSet backed by a 20Gi, expandable GKE
balanced Persistent Disk via `standard-rwo`. This initial deployment is not a
high-availability MySQL topology.

## Secret contract

GitHub environment `Development` must provide:

- `TESTUDO_DEV_GCP_SA_KEY`
- `CLOUDFLARE_API_TOKEN_DEV`
- `CLOUDFLARE_ZONE_ID_DEV`
- `FLEET_SECRETS_ENV`
- `FLEET_BACKUP_GCP_SA_KEY` (dedicated `fleet-backup` service account,
  restricted to object creation plus read/list in the backup bucket; it cannot
  delete objects or administer the bucket)

`FLEET_SECRETS_ENV` is a newline-delimited env file containing only these keys:

```text
mysql-password=<random value>
mysql-root-password=<different random value>
redis-password=<random value>
fleet-server-private-key=<at least 32 random bytes>
```

The environment variable `GCP_DEV_PROJECT` must be `testudo-dev`. No secret
file belongs in Git. The workflow materializes `fleet-secrets` directly in the
cluster and deletes its temporary runner file.

## Deployment order

The workflow applies the namespace and secret, MySQL, Redis, restrictive
database NetworkPolicies, the explicit `fleet prepare db --no-prompt` Job,
Fleet, the GCE Ingress, Cloudflare DNS, and HTTPS smoke tests. `/healthz` is the
Fleet health endpoint and checks both MySQL and Redis.

For a manual deployment, follow the same order shown in
`.github/workflows/deploy-gke-testudo.yml`; do not apply the whole overlay to a
fresh database before running the migration Job.

## Persistence test

After HTTPS is healthy, run:

```bash
bash scripts/testudo/test-mysql-persistence.sh
```

The script records the PVC UID, Persistent Disk name, and Fleet schema table
count, deletes `mysql-0`, waits for recreation, and proves all three persisted
before checking public `/healthz` again.

## Backups

`mysql-backup` runs daily at 02:17 UTC. It performs a consistent
`mysqldump --single-transaction` and uploads the compressed result to
`gs://testudo-dev-fleet-mysql-backups/mysql/`. The cluster advertises Workload
Identity, but its Autopilot metadata endpoint rejects workload tokens on the
current node pool; therefore the CronJob uses a dedicated, least-privilege GSA
key stored as a Kubernetes/GitHub secret. Re-test Workload Identity after a
cluster upgrade and remove the static key when the metadata endpoint works.
Backups are outside the MySQL Persistent Disk. Restore tests should be scheduled
periodically in a disposable database; a backup is not proven until restored.

## Apple MDM readiness

The deployment supplies the stable public HTTPS URL and a durable, secret
`FLEET_SERVER_PRIVATE_KEY`, which Fleet requires for MDM encryption. Complete
Apple enablement later in Fleet settings; legacy APNs/SCEP environment
variables are deprecated since Fleet 4.51.

The remaining external prerequisites are:

1. An Apple Push Certificates Portal certificate generated for Fleet and its
   private key (APNs).
2. An Apple Business Manager account with Testudo administrator access.
3. An ABM MDM server token uploaded to Fleet, with Fleet's public key/certificate
   exchanged in ABM and the token renewed before expiry.
4. Automated Device Enrollment profiles assigned in Fleet and the Testudo Mac
   serial numbers assigned to the Fleet MDM server in ABM.
5. For already deployed Macs, either manual enrollment or a planned migration
   from the current MDM; for new Macs, erase/Setup Assistant activation after
   ADE assignment.
6. Optional package/object storage configuration if software installers or an
   ADE bootstrap package are enabled. Fleet's self-hosted package workflow
   requires S3-compatible storage; do not reuse the MySQL backup bucket without
   a deliberate IAM and lifecycle design.
