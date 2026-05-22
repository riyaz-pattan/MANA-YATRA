#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

PROJECT_ID="mana-yatra"
LOCATION="us-central1"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo "      Mana Yatra - Cloud Functions Lifecycle Setup"
echo "=========================================================="
echo ""

# -----------------------------------------------------------------------------
# STEP 1: Apply Option A - Standard 7-day Policy via Firebase CLI
# -----------------------------------------------------------------------------
echo "--> STEP 1: Applying Standard 7-day Policy via Firebase CLI..."
if command -v firebase >/dev/null 2>&1; then
  echo "Firebase CLI found. Running setpolicy command..."
  firebase functions:artifacts:setpolicy --days 7 --location "$LOCATION" --force
  echo "Standard 7-day policy successfully set on 'gcf-artifacts' repository!"
else
  echo "WARNING: Firebase CLI not found in the current terminal environment."
  echo "Please run this command manually once Firebase CLI is available:"
  echo "  firebase functions:artifacts:setpolicy --days 7 --location $LOCATION --force"
fi
echo ""

# -----------------------------------------------------------------------------
# STEP 2: Generate Advanced Cloud Shell Script
# -----------------------------------------------------------------------------
echo "--> STEP 2: Generating 'cloud-shell-setup.sh' for advanced GCS/Registry policies..."

CLOUD_SHELL_SCRIPT="${SCRIPTS_DIR}/cloud-shell-setup.sh"

cat << 'EOF' > "$CLOUD_SHELL_SCRIPT"
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
EOF

chmod +x "$CLOUD_SHELL_SCRIPT"
echo "Generated script: ${CLOUD_SHELL_SCRIPT}"
echo ""
echo "=========================================================="
echo "Next Steps:"
echo "1. Run the local script to set the standard policy (Option A)."
echo "2. Copy 'scripts/cloud-shell-setup.sh' and run it in Google Cloud Shell"
echo "   to apply GCS bucket policies and the advanced Keep/Delete rule!"
echo "=========================================================="
