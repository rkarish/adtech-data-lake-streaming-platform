-- Flink SQL DML: Streaming inserts from Kafka into Iceberg

-- Checkpoint configuration
SET 'execution.checkpointing.interval' = '60s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';
SET 'state.checkpoints.dir' = 's3://warehouse/checkpoints/';

EXECUTE STATEMENT SET
BEGIN

-- Insert bid_requests: flatten nested JSON into Iceberg table
-- Supports both site and app traffic (mutually exclusive)
-- Filters out test publishers (test-*) and private IPs for clean analytics
INSERT INTO iceberg_catalog.db.bid_requests
SELECT
    `id` AS request_id,
    `imp`[1].`id` AS imp_id,
    `imp`[1].`banner`.`w` AS imp_banner_w,
    `imp`[1].`banner`.`h` AS imp_banner_h,
    `imp`[1].`bidfloor` AS imp_bidfloor,
    COALESCE(`site`.`id`, `app`.`id`) AS site_id,
    COALESCE(`site`.`domain`, `app`.`bundle`) AS site_domain,
    COALESCE(`site`.`cat`, `app`.`cat`) AS site_cat,
    COALESCE(`site`.`publisher`.`id`, `app`.`publisher`.`id`) AS publisher_id,
    `device`.`devicetype` AS device_type,
    `device`.`os` AS device_os,
    `device`.`geo`.`country` AS device_geo_country,
    `device`.`geo`.`region` AS device_geo_region,
    `user`.`id` AS user_id,
    `at` AS auction_type,
    `tmax` AS tmax,
    `cur`[1] AS currency,
    CASE WHEN `regs`.`coppa` = 1 THEN TRUE ELSE FALSE END AS is_coppa,
    CASE WHEN `regs`.`ext`.`gdpr` = 1 THEN TRUE ELSE FALSE END AS is_gdpr,
    CAST(
        TO_TIMESTAMP(SUBSTRING(`event_timestamp`, 1, 26), 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
        AS TIMESTAMP_LTZ(6)
    ) AS event_timestamp,
    CAST(
        TO_TIMESTAMP(SUBSTRING(`received_at`, 1, 26), 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
        AS TIMESTAMP_LTZ(6)
    ) AS received_at
FROM kafka_bid_requests
WHERE
    -- Exclude test publishers
    COALESCE(`site`.`publisher`.`id`, `app`.`publisher`.`id`) NOT LIKE 'test-%'
    -- Exclude private IPs (RFC1918 ranges)
    AND `device`.`ip` NOT LIKE '10.%'
    AND `device`.`ip` NOT LIKE '192.168.%'
    AND `device`.`ip` NOT LIKE '172.16.%'
    AND `device`.`ip` NOT LIKE '172.17.%'
    AND `device`.`ip` NOT LIKE '172.18.%'
    AND `device`.`ip` NOT LIKE '172.19.%'
    AND `device`.`ip` NOT LIKE '172.2_.%'
    AND `device`.`ip` NOT LIKE '172.30.%'
    AND `device`.`ip` NOT LIKE '172.31.%'
    -- Ensure valid bid floor
    AND `imp`[1].`bidfloor` > 0;

-- Insert bid_requests_enriched: includes device classification, currency normalization, and traffic flags
-- This table captures ALL traffic (including test and invalid) for analysis
INSERT INTO iceberg_catalog.db.bid_requests_enriched
SELECT
    `id` AS request_id,
    `imp`[1].`id` AS imp_id,
    `imp`[1].`banner`.`w` AS imp_banner_w,
    `imp`[1].`banner`.`h` AS imp_banner_h,
    `imp`[1].`bidfloor` AS imp_bidfloor,
    -- Currency normalization: convert bid floor to USD using static exchange rates
    CASE `imp`[1].`bidfloorcur`
        WHEN 'EUR' THEN `imp`[1].`bidfloor` * 1.08
        WHEN 'GBP' THEN `imp`[1].`bidfloor` * 1.25
        WHEN 'JPY' THEN `imp`[1].`bidfloor` * 0.0067
        ELSE `imp`[1].`bidfloor`
    END AS imp_bidfloor_usd,
    `imp`[1].`bidfloorcur` AS imp_bidfloorcur,
    `site`.`id` AS site_id,
    `site`.`domain` AS site_domain,
    `app`.`id` AS app_id,
    `app`.`bundle` AS app_bundle,
    COALESCE(`site`.`publisher`.`id`, `app`.`publisher`.`id`) AS publisher_id,
    `device`.`devicetype` AS device_type,
    `device`.`os` AS device_os,
    `device`.`ip` AS device_ip,
    `device`.`geo`.`country` AS device_geo_country,
    `device`.`geo`.`region` AS device_geo_region,
    -- Device classification based on device type and site/app presence
    CASE
        WHEN `device`.`devicetype` = 7 THEN 'CTV'
        WHEN `device`.`devicetype` IN (1, 4) AND `app`.`id` IS NOT NULL THEN 'Mobile App'
        WHEN `device`.`devicetype` IN (1, 4) AND `site`.`id` IS NOT NULL THEN 'Mobile Web'
        WHEN `device`.`devicetype` = 2 THEN 'Desktop'
        ELSE 'Unknown'
    END AS device_category,
    `user`.`id` AS user_id,
    `at` AS auction_type,
    `cur`[1] AS currency,
    CASE WHEN `regs`.`coppa` = 1 THEN TRUE ELSE FALSE END AS is_coppa,
    CASE WHEN `regs`.`ext`.`gdpr` = 1 THEN TRUE ELSE FALSE END AS is_gdpr,
    -- Test traffic flag: publisher ID starts with 'test-'
    CASE
        WHEN COALESCE(`site`.`publisher`.`id`, `app`.`publisher`.`id`) LIKE 'test-%' THEN TRUE
        ELSE FALSE
    END AS is_test_traffic,
    -- Private IP flag: RFC1918 private IP ranges
    CASE
        WHEN `device`.`ip` LIKE '10.%'
            OR `device`.`ip` LIKE '192.168.%'
            OR `device`.`ip` LIKE '172.16.%'
            OR `device`.`ip` LIKE '172.17.%'
            OR `device`.`ip` LIKE '172.18.%'
            OR `device`.`ip` LIKE '172.19.%'
            OR `device`.`ip` LIKE '172.2_.%'
            OR `device`.`ip` LIKE '172.30.%'
            OR `device`.`ip` LIKE '172.31.%'
        THEN TRUE
        ELSE FALSE
    END AS is_private_ip,
    CAST(
        TO_TIMESTAMP(SUBSTRING(`event_timestamp`, 1, 26), 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
        AS TIMESTAMP_LTZ(6)
    ) AS event_timestamp,
    CAST(
        TO_TIMESTAMP(SUBSTRING(`received_at`, 1, 26), 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
        AS TIMESTAMP_LTZ(6)
    ) AS received_at
FROM kafka_bid_requests;

-- Insert bid_responses: flatten nested seatbid[].bid[] into Iceberg table
INSERT INTO iceberg_catalog.db.bid_responses
SELECT
    `id` AS response_id,
    `ext`.`request_id` AS request_id,
    `seatbid`[1].`seat` AS seat,
    `seatbid`[1].`bid`[1].`id` AS bid_id,
    `seatbid`[1].`bid`[1].`impid` AS imp_id,
    `seatbid`[1].`bid`[1].`price` AS bid_price,
    `seatbid`[1].`bid`[1].`crid` AS creative_id,
    `seatbid`[1].`bid`[1].`dealid` AS deal_id,
    `seatbid`[1].`bid`[1].`adomain`[1] AS ad_domain,
    `cur` AS currency,
    CAST(
        TO_TIMESTAMP(SUBSTRING(`event_timestamp`, 1, 26), 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
        AS TIMESTAMP_LTZ(6)
    ) AS event_timestamp
FROM kafka_bid_responses;

-- Insert impressions: flat structure, 1:1 mapping
INSERT INTO iceberg_catalog.db.impressions
SELECT
    `impression_id`,
    `request_id`,
    `response_id`,
    `imp_id`,
    `bidder_id`,
    `win_price`,
    `win_currency`,
    `creative_id`,
    `ad_domain`,
    CAST(
        TO_TIMESTAMP(SUBSTRING(`event_timestamp`, 1, 26), 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
        AS TIMESTAMP_LTZ(6)
    ) AS event_timestamp
FROM kafka_impressions;

-- Insert clicks: flat structure, 1:1 mapping
INSERT INTO iceberg_catalog.db.clicks
SELECT
    `click_id`,
    `request_id`,
    `impression_id`,
    `imp_id`,
    `bidder_id`,
    `creative_id`,
    `click_url`,
    CAST(
        TO_TIMESTAMP(SUBSTRING(`event_timestamp`, 1, 26), 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS')
        AS TIMESTAMP_LTZ(6)
    ) AS event_timestamp
FROM kafka_clicks;

END;
