# AdTech Data Lake Streaming Platform

A data lake streaming platform for adtech that produces OpenRTB 2.6 bid request events to Apache Kafka, streams them through Apache Flink, and stores them in Apache Iceberg tables backed by MinIO (S3-compatible) object storage.

See [`.design/adtech-data-lake-streaming-platform.md`](.design/adtech-data-lake-streaming-platform.md) for the full design document.

## Architecture

```
Mock Data Gen  --->  Kafka (KRaft)
                         |
                         v
                   Flink (SQL Job)
                         |
              +----------+----------+
              |                     |
        Iceberg REST            MinIO (S3)
         Catalog                    |
              |              Iceberg Tables
              |             (Parquet files)
              |                     |
              +----------+----------+
                         |
                   Trino (Query)
                         |
              +----------+----------+
              |                     |
        CloudBeaver           Superset
       (Web SQL IDE)         (Dashboards)
```

**Services:**

| Service | Image | Ports |
|---|---|---|
| `kafka` | `apache/kafka:3.8.1` (KRaft) | 29092 (host), 9092 (internal) |
| `minio` | `minio/minio:latest` | 9000 (S3), 9001 (console) |
| `iceberg-rest` | `tabulario/iceberg-rest:0.10.0` | 8181 |
| `mock-data-gen` | Custom (Python 3.12) | -- |
| `flink-jobmanager` | Custom (Flink 1.20 + Iceberg) | 8081 (Web UI) |
| `flink-taskmanager` | Custom (Flink 1.20 + Iceberg) | -- |
| `trino` | `trinodb/trino:467` | 8080 (Web UI) |
| `cloudbeaver` | `dbeaver/cloudbeaver:latest` | 8978 (Web UI) |
| `superset` | Custom (apache/superset + trino driver) | 8088 (Web UI) |
| `superset-postgres` | `postgres:16-alpine` | internal only |

## Prerequisites

- Docker and Docker Compose
- Python 3.12+ (for local development only)
- `curl` (for setup script)

## Quick Start (Docker)

### 1. Build and start all services

```bash
docker compose up --build -d
```

This starts the infrastructure services (Kafka, MinIO, Iceberg, Flink, Trino, CloudBeaver, Superset) but **not** the mock data generator. To also start the generator (continuous event stream):

```bash
docker compose --profile generator up --build -d
```

Wait for all services to become healthy:

```bash
docker compose ps
```

### 2. Run the setup script

Creates the Kafka topic, MinIO bucket, Iceberg namespace + table, submits the Flink streaming job, and verifies Trino connectivity:

```bash
bash scripts/setup.sh
```

### 3. Verify

Check that bid request events are flowing through Kafka:

```bash
docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic bid-requests \
  --from-beginning \
  --max-messages 3
```

Verify the Flink job is running:

```bash
curl -s http://localhost:8081/jobs | python3 -m json.tool
```

Check that Parquet files appear in MinIO (after the first checkpoint, ~60s):

```bash
docker compose exec minio mc ls --recursive local/warehouse/db/bid_requests/
```

Open the Flink Web UI at [http://localhost:8081](http://localhost:8081) to monitor records received/sent.

Verify the Iceberg table exists:

```bash
curl -s http://localhost:8181/v1/namespaces/db/tables | python3 -m json.tool
```

Check the MinIO bucket:

```bash
docker exec minio mc ls local/warehouse/
```

View generator logs:

```bash
docker compose logs mock-data-gen --tail 20
```

### 4. Read data from Kafka

Consume a few messages from the topic:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic bid-requests \
  --from-beginning \
  --max-messages 5
```

Pipe through `python3` for pretty-printed JSON:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic bid-requests \
  --from-beginning \
  --max-messages 1 | python3 -m json.tool
```

Check topic offsets (total message count per partition):

```bash
docker compose exec kafka /opt/kafka/bin/kafka-get-offsets.sh \
  --bootstrap-server localhost:9092 \
  --topic bid-requests
```

Tail new messages in real time (Ctrl+C to stop):

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic bid-requests
```

### 5. Query the Iceberg table (Flink SQL)

Open a Flink SQL Client session:

```bash
docker compose exec flink-jobmanager /opt/flink/bin/sql-client.sh embedded
```

Register the Iceberg catalog (required each session):

```sql
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'rest',
    'uri' = 'http://iceberg-rest:8181',
    'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
    's3.endpoint' = 'http://minio:9000',
    's3.path-style-access' = 'true',
    'warehouse' = 's3://warehouse/'
);
```

Switch to batch mode (without this, queries run in streaming mode and never finish):

```sql
SET 'execution.runtime-mode' = 'batch';
```

Run queries:

```sql
-- Preview rows
SELECT * FROM iceberg_catalog.db.bid_requests LIMIT 10;

-- Count total records
SELECT COUNT(*) FROM iceberg_catalog.db.bid_requests;

-- Aggregation example
SELECT device_geo_country, COUNT(*) AS cnt
FROM iceberg_catalog.db.bid_requests
GROUP BY device_geo_country
ORDER BY cnt DESC;
```

Type `QUIT;` to exit the SQL client.

### 6. Query with Trino

Trino provides a standard SQL interface to the Iceberg tables. Run an ad-hoc query:

```bash
docker exec trino trino --catalog iceberg --schema db \
  --execute "SELECT device_geo_country, COUNT(*) AS cnt FROM bid_requests GROUP BY device_geo_country ORDER BY cnt DESC LIMIT 5"
```

Run the full set of sample analytical queries:

```bash
bash scripts/query-examples.sh
```

The Trino Web UI is available at [http://localhost:8080](http://localhost:8080) (no credentials required).

### 7. Table Maintenance

Run Iceberg table maintenance (compaction, snapshot expiry, orphan cleanup) via Trino:

```bash
bash scripts/maintenance.sh
```

### 8. CloudBeaver (Web SQL IDE)

Open [http://localhost:8978](http://localhost:8978). On the first launch you will need to complete the setup wizard:

1. Set an admin password (must meet complexity requirements, e.g. `Password123!`)
2. Finish the wizard

Once configured, click the CloudBeaver logo in the top-left corner to reach the main database UI. The pre-configured "Trino Iceberg" connection appears in the sidebar. Expand it to browse the `iceberg > db > bid_requests` table and run SQL queries.

The workspace is persisted in a Docker volume (`cloudbeaver-workspace`), so subsequent restarts will skip the wizard.

### 9. Superset (Charts & SQL Lab)

Open [http://localhost:8088](http://localhost:8088) and log in with `admin` / `password`. The setup script creates:

- A Trino database connection
- A `bid_requests` dataset
- A "Bid Requests by Country" pie chart (visible under Charts)

You can also use SQL Lab to run ad-hoc queries against Trino.

### 10. Stop

```bash
docker compose down
```

## Local Development (without Docker for the generator)

You can run the mock data generator outside Docker while keeping Kafka, Flink, and the other infrastructure services in Docker.

### 1. Build and start infrastructure services

```bash
docker compose build flink-jobmanager flink-taskmanager
docker compose up kafka minio iceberg-rest trino flink-jobmanager flink-taskmanager -d
```

Wait for all services to become healthy:

```bash
docker compose ps
```

### 2. Run the setup script

Creates the Kafka topic, MinIO bucket, Iceberg namespace + table, submits the Flink streaming job, and verifies Trino connectivity:

```bash
bash scripts/setup.sh
```

### 3. Run the generator locally

This creates a `.venv` virtual environment, installs dependencies, and starts the generator:

```bash
bash scripts/run-local.sh
```

You can override settings via environment variables:

```bash
EVENTS_PER_SECOND=50 bash scripts/run-local.sh
```

Or set up the environment manually:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install ./mock-data-gen
cd mock-data-gen
KAFKA_BOOTSTRAP_SERVERS=localhost:29092 python -m src.generator
```

### 4. Verify the Flink pipeline

Check that the Flink job is running:

```bash
curl -s http://localhost:8081/jobs | python3 -m json.tool
```

Open the Flink Web UI at [http://localhost:8081](http://localhost:8081) to monitor records received/sent.

After ~60 seconds (first Flink checkpoint), verify Parquet files are landing in MinIO:

```bash
docker compose exec minio mc ls --recursive local/warehouse/db/bid_requests/
```

## Configuration

### Mock Data Generator

| Variable | Default | Description |
|---|---|---|
| `KAFKA_BOOTSTRAP_SERVERS` | `kafka:9092` (Docker) / `localhost:29092` (local) | Kafka broker address |
| `EVENTS_PER_SECOND` | `10` | Target event throughput |
| `TOPIC_BID_REQUESTS` | `bid-requests` | Kafka topic name |

### Flink Web UI

Access the Flink dashboard at [http://localhost:8081](http://localhost:8081) to monitor running jobs, checkpoints, and task metrics.

### Trino

Access the Trino Web UI at [http://localhost:8080](http://localhost:8080) (no credentials required). Run queries via CLI:

```bash
docker exec trino trino --catalog iceberg --schema db
```

### MinIO Console

Access the MinIO web console at [http://localhost:9001](http://localhost:9001) with credentials `admin` / `password`.

### Iceberg REST Catalog

The catalog API is available at [http://localhost:8181](http://localhost:8181). List tables:

```bash
curl -s http://localhost:8181/v1/namespaces/db/tables | python3 -m json.tool
```

### CloudBeaver

Access the CloudBeaver web SQL IDE at [http://localhost:8978](http://localhost:8978) with credentials `admin` / `password`. A Trino connection is pre-configured and available immediately.

### Superset

Access Superset at [http://localhost:8088](http://localhost:8088) with credentials `admin` / `password`. The Trino connection, dataset, and a sample chart are created automatically by the setup script. Superset uses a dedicated PostgreSQL instance (`superset-postgres`) for metadata and `SimpleCache` (in-memory) instead of Redis.

## Project Structure

```
streaming-data-lake/
  .design/
    adtech-streaming-platform.md   # Design document
  docker-compose.yml               # All local services
  mock-data-gen/
    pyproject.toml                 # Python dependencies
    Dockerfile                     # Container image
    src/
      config.py                    # Configuration from env vars
      schemas.py                   # OpenRTB 2.6 BidRequest generator
      generator.py                 # Kafka producer loop
  streaming/
    flink/
      Dockerfile                   # Custom Flink 1.20 image with Iceberg JARs
      submit-sql-job.sh            # Waits for deps, submits SQL job
      sql/
        create_tables.sql          # Flink SQL DDL (catalogs + source tables)
        insert_jobs.sql            # Flink SQL DML (streaming insert)
  trino/
    catalog/
      iceberg.properties           # Iceberg connector config for Trino
  cloudbeaver/
    initial-data-sources.conf      # Pre-configured Trino JDBC connection
    initial-data.conf              # Admin credentials (skip setup wizard)
  superset/
    Dockerfile                     # Custom Superset image with Trino driver
    superset_config.py             # Superset configuration (SimpleCache, no Redis)
    bootstrap.sh                   # DB migration, admin creation, server start
    setup-dashboards.py            # REST API script to create dashboards
  scripts/
    setup.sh                       # Initialize topics, bucket, tables, Flink job, verify Trino, setup dashboards
    run-local.sh                   # Run generator in local .venv
    query-examples.sh              # Sample analytical queries via Trino
    maintenance.sh                 # Iceberg table maintenance (compaction, expiry, cleanup)
```
