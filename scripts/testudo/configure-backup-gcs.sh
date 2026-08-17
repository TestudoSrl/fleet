#!/usr/bin/env bash
set -euo pipefail

project="${GCP_PROJECT:-testudo-dev}"
region="${GCP_REGION:-europe-west1}"
namespace="${FLEET_NAMESPACE:-fleet}"
bucket="${FLEET_BACKUP_BUCKET:-testudo-dev-fleet-mysql-backups}"
gsa_name="fleet-backup"
gsa="${gsa_name}@${project}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "${gsa}" --project "${project}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${gsa_name}" \
    --project "${project}" \
    --display-name "Fleet MySQL backup uploader"
fi

if ! gcloud storage buckets describe "gs://${bucket}" --project "${project}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${bucket}" \
    --project "${project}" \
    --location "${region}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
  --member "serviceAccount:${gsa}" \
  --role roles/storage.objectCreator \
  --project "${project}" >/dev/null

# gcloud storage checks destination object existence before uploading. Pair
# objectCreator with read/list, without granting delete or bucket administration.
gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
  --member "serviceAccount:${gsa}" \
  --role roles/storage.objectViewer \
  --project "${project}" >/dev/null

gcloud iam service-accounts add-iam-policy-binding "${gsa}" \
  --project "${project}" \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${project}.svc.id.goog[${namespace}/fleet-backup]" \
  --condition=None >/dev/null

kubectl -n "${namespace}" annotate serviceaccount fleet-backup \
  "iam.gke.io/gcp-service-account=${gsa}" --overwrite >/dev/null

echo "Backup identity and off-cluster bucket are configured."
