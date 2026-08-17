#!/usr/bin/env bash
set -euo pipefail

namespace="${FLEET_NAMESPACE:-fleet}"
pvc="mysql-data-mysql-0"

before_uid="$(kubectl -n "${namespace}" get pvc "${pvc}" -o jsonpath='{.metadata.uid}')"
before_volume="$(kubectl -n "${namespace}" get pvc "${pvc}" -o jsonpath='{.spec.volumeName}')"
before_tables="$(kubectl -n "${namespace}" exec mysql-0 -- sh -ec \
  'mysql --batch --skip-column-names -u fleet -p"$MYSQL_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"fleet\""')"

test -n "${before_uid}"
test -n "${before_volume}"
test "${before_tables}" -gt 0

kubectl -n "${namespace}" delete pod mysql-0 --wait=true
kubectl -n "${namespace}" wait --for=condition=Ready pod/mysql-0 --timeout=15m

after_uid="$(kubectl -n "${namespace}" get pvc "${pvc}" -o jsonpath='{.metadata.uid}')"
after_volume="$(kubectl -n "${namespace}" get pvc "${pvc}" -o jsonpath='{.spec.volumeName}')"
after_tables="$(kubectl -n "${namespace}" exec mysql-0 -- sh -ec \
  'mysql --batch --skip-column-names -u fleet -p"$MYSQL_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"fleet\""')"

test "${before_uid}" = "${after_uid}"
test "${before_volume}" = "${after_volume}"
test "${before_tables}" = "${after_tables}"
kubectl -n "${namespace}" rollout status deployment/fleet --timeout=10m
curl -fsS --retry 30 --retry-all-errors --retry-delay 5 \
  https://mdm.testudosrl.dev/healthz >/dev/null

echo "MySQL persistence verified: same PVC, same Persistent Disk, Fleet data intact."

