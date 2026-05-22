#!/bin/bash
set -e

PROJECT_ID="mana-yatra"
LOCATION="us-central1"

echo "=========================================================="
echo "    Executing Advanced GCP Cleanup Policies (Cloud Shell)"
echo "=========================================================="
echo ""

# 1. Apply GCS Lifecycle Policy to gcf-sources buckets
echo "--> 1. Locating Cloud Functions GCS source buckets..."
BUCKETS=$(gcloud storage buckets list --project="$PROJECT_ID" --format="value(name)" | grep -E '^gcf-sources-' || true)

if [ -n "$BUCKETS" ]; then
  # Create temporary lifecycle config
  cat << 'JSON' > gcs-lifecycle-temp.json
{
  "rule": [
    {
      "action": {
        "type": "Delete"
      },
      "condition": {
        "age": 7
      }
    }
  ]
}
JSON

  for bucket in $BUCKETS; do
    echo "Applying 7-day lifecycle policy to GCS bucket: gs://${bucket}..."
    gcloud storage buckets update gs://${bucket} --lifecycle-file=gcs-lifecycle-temp.json
  done
  rm gcs-lifecycle-temp.json
  echo "GCS source bucket lifecycle policies configured successfully!"
else
  echo "No 'gcf-sources-' buckets found in project '$PROJECT_ID'."
fi
echo ""

# 2. Apply Custom Combined Keep-and-Delete Policy to Artifact Registry
echo "--> 2. Applying Advanced Keep-and-Delete Policy to Artifact Registry..."

# Create temporary policy file
cat << 'JSON' > gcp-cleanup-policy-temp.json
[
  {
    "name": "keep-recent-versions",
    "action": {
      "type": "KEEP"
    },
    "mostRecentVersions": {
      "keepCount": 3
    }
  },
  {
    "name": "delete-old-versions",
    "action": {
      "type": "DELETE"
    },
    "condition": {
      "tagState": "ANY",
      "olderThan": "7d"
    }
  }
]
JSON

# Apply the policy
echo "Setting cleanup policies on repository 'gcf-artifacts'..."
gcloud artifacts repositories set-cleanup-policies gcf-artifacts \
    --project="$PROJECT_ID" \
    --location="$LOCATION" \
    --policy=gcp-cleanup-policy-temp.json

rm gcp-cleanup-policy-temp.json

echo ""
echo "=========================================================="
echo "SUCCESS: Advanced Keep/Delete and GCS policies are active!"
echo "=========================================================="
