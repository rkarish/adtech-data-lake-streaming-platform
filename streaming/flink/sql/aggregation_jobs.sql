-- Flink SQL DML: Streaming aggregations to Iceberg tables
-- These jobs use windowing and write to upsert-enabled tables with primary keys
-- Run as a separate Flink job from the main insert_jobs.sql for independent lifecycle

-- Checkpoint configuration for aggregation jobs (separate checkpoint directory)
SET 'execution.checkpointing.interval' = '60s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'state.checkpoints.dir' = 's3://warehouse/checkpoints/aggregations/';

-- Configure state TTL for windowed operations (24 hours, cleans up old state)
SET 'table.exec.state.ttl' = '86400000';

EXECUTE STATEMENT SET
BEGIN

-- Hourly impressions by bidder: tumbling 1-hour window
-- Computes impression counts and revenue metrics grouped by bidder seat
-- Note: Geo-based aggregation would require joining with bid_requests (deferred to Phase 7)
-- Uses upsert mode to update aggregates as new data arrives
-- Uses event_ts (computed column with watermark) for event-time windowing
-- Uses explicit Flink sink table with upsert-enabled for proper Iceberg writes
INSERT INTO iceberg_hourly_impressions_by_geo
SELECT
    TUMBLE_START(`event_ts`, INTERVAL '1' HOUR) AS window_start,
    `bidder_id` AS device_geo_country,
    COUNT(*) AS impression_count,
    SUM(`win_price`) AS total_revenue,
    AVG(`win_price`) AS avg_win_price
FROM kafka_impressions
GROUP BY
    TUMBLE(`event_ts`, INTERVAL '1' HOUR),
    `bidder_id`;

-- Rolling 5-minute metrics by bidder: sliding window (1-min hop, 5-min size)
-- Provides near-real-time metrics for dashboards, updated every minute
-- Uses explicit Flink sink table with upsert-enabled for proper Iceberg writes
INSERT INTO iceberg_rolling_metrics_by_bidder
SELECT
    HOP_START(`event_ts`, INTERVAL '1' MINUTE, INTERVAL '5' MINUTES) AS window_start,
    HOP_END(`event_ts`, INTERVAL '1' MINUTE, INTERVAL '5' MINUTES) AS window_end,
    `bidder_id`,
    COUNT(*) AS win_count,
    SUM(`win_price`) AS revenue,
    AVG(`win_price`) AS avg_cpm
FROM kafka_impressions
GROUP BY
    HOP(`event_ts`, INTERVAL '1' MINUTE, INTERVAL '5' MINUTES),
    `bidder_id`;

END;
