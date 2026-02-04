#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# AdTech Data Lake Streaming Platform - Table Maintenance
# =============================================================================
# Runs Iceberg table maintenance operations via Trino:
#   1. Compaction (optimize small files)
#   2. Snapshot expiry (remove old snapshots)
#   3. Orphan file cleanup (remove unreferenced files)
#
# Prerequisites: docker compose up -d && bash scripts/setup.sh
# =============================================================================

TRINO="docker exec trino trino --catalog iceberg --schema db"

echo "==> Starting Iceberg table maintenance for 'db.bid_requests'..."

# ---- 1. Compaction ----
echo ""
echo "==> [1/3] Compacting small files (target: 128MB)..."
${TRINO} --execute \
  "ALTER TABLE bid_requests EXECUTE optimize(file_size_threshold => '128MB')"
echo "    Compaction complete."

# ---- 2. Snapshot expiry ----
echo ""
echo "==> [2/3] Expiring snapshots older than 7 days..."
${TRINO} --execute \
  "ALTER TABLE bid_requests EXECUTE expire_snapshots(retention_threshold => '7d')"
echo "    Snapshot expiry complete."

# ---- 3. Orphan file cleanup ----
echo ""
echo "==> [3/3] Removing orphan files older than 7 days..."
${TRINO} --execute \
  "ALTER TABLE bid_requests EXECUTE remove_orphan_files(retention_threshold => '7d')"
echo "    Orphan file cleanup complete."

echo ""
echo "==> Table maintenance complete."
