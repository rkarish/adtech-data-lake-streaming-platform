#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# AdTech Data Lake Streaming Platform - Sample Analytical Queries
# =============================================================================
# Runs example queries against the Iceberg bid_requests table via Trino.
# Prerequisites: docker compose up -d && bash scripts/setup.sh
# =============================================================================

TRINO="docker exec trino trino --catalog iceberg --schema db"

run_query() {
  local title="$1"
  local sql="$2"
  echo ""
  echo "==> ${title}"
  echo "---"
  ${TRINO} --execute "${sql}"
  echo ""
}

# ---- 1. Request volume by country ----
run_query "Request volume by country (top 10)" \
  "SELECT device_geo_country, COUNT(*) AS request_count
   FROM bid_requests
   GROUP BY device_geo_country
   ORDER BY request_count DESC
   LIMIT 10"

# ---- 2. Average bid floor by country/region ----
run_query "Average bid floor by country and region (top 10)" \
  "SELECT device_geo_country, device_geo_region,
          ROUND(AVG(imp_bidfloor), 4) AS avg_bidfloor,
          COUNT(*) AS request_count
   FROM bid_requests
   GROUP BY device_geo_country, device_geo_region
   ORDER BY avg_bidfloor DESC
   LIMIT 10"

# ---- 3. Bid floor distribution by ad size ----
run_query "Bid floor distribution by ad size" \
  "SELECT imp_banner_w, imp_banner_h,
          ROUND(MIN(imp_bidfloor), 4) AS min_floor,
          ROUND(AVG(imp_bidfloor), 4) AS avg_floor,
          ROUND(MAX(imp_bidfloor), 4) AS max_floor,
          COUNT(*) AS request_count
   FROM bid_requests
   GROUP BY imp_banner_w, imp_banner_h
   ORDER BY request_count DESC
   LIMIT 10"

# ---- 4. Device OS and type breakdown ----
run_query "Device OS and type breakdown" \
  "SELECT device_os, device_type, COUNT(*) AS request_count
   FROM bid_requests
   GROUP BY device_os, device_type
   ORDER BY request_count DESC"

# ---- 5. Hourly request volume ----
run_query "Hourly request volume" \
  "SELECT date_trunc('hour', event_timestamp) AS hour,
          COUNT(*) AS request_count
   FROM bid_requests
   GROUP BY date_trunc('hour', event_timestamp)
   ORDER BY hour DESC
   LIMIT 24"

# ---- 6. Auction type distribution ----
run_query "Auction type distribution" \
  "SELECT auction_type,
          CASE auction_type
            WHEN 1 THEN 'First Price'
            WHEN 2 THEN 'Second Price'
            ELSE 'Other'
          END AS auction_name,
          COUNT(*) AS request_count
   FROM bid_requests
   GROUP BY auction_type
   ORDER BY request_count DESC"

# ---- 7. GDPR/COPPA flag distribution ----
run_query "GDPR and COPPA flag distribution" \
  "SELECT is_gdpr, is_coppa, COUNT(*) AS request_count
   FROM bid_requests
   GROUP BY is_gdpr, is_coppa
   ORDER BY request_count DESC"

# ---- 8. Iceberg snapshot metadata (time travel) ----
run_query "Iceberg snapshot history" \
  "SELECT snapshot_id, parent_id, committed_at, operation, summary
   FROM iceberg.db.\"bid_requests\$snapshots\"
   ORDER BY committed_at DESC
   LIMIT 10"

echo "==> All queries completed."
