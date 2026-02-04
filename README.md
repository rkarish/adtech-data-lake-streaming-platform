# AdTech Streaming Data Platform

A streaming data platform for adtech that produces OpenRTB 2.6 bid request events to Apache Kafka and stores them in Apache Iceberg tables backed by MinIO (S3-compatible) object storage.

See [`.design/adtech-streaming-platform.md`](.design/adtech-streaming-platform.md) for the full design document.

## Architecture (Phase 1)

```
Mock Data Gen  --->  Kafka (KRaft)
                         |
                         v
                   (Phase 2: Flink)
                         |
              +----------+----------+
              |                     |
        Iceberg REST            MinIO (S3)
         Catalog                    |
                              Iceberg Tables
                             (Parquet files)
```

**Services:**

| Service | Image | Ports |
|---|---|---|
| `kafka` | `apache/kafka:3.8.1` (KRaft) | 29092 (host), 9092 (internal) |
| `minio` | `minio/minio:latest` | 9000 (S3), 9001 (console) |
| `iceberg-rest` | `tabulario/iceberg-rest:0.10.0` | 8181 |
| `mock-data-gen` | Custom (Python 3.12) | -- |

## Prerequisites

- Docker and Docker Compose
- Python 3.12+ (for local development only)
- `curl` (for setup script)

## Quick Start (Docker)

### 1. Start all services

```bash
docker compose up -d
```

Wait for all services to become healthy:

```bash
docker compose ps
```

### 2. Run the setup script

Creates the Kafka topic, MinIO bucket, and Iceberg namespace + table:

```bash
bash scripts/setup.sh
```

### 3. Verify

Check that bid request events are flowing:

```bash
docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic bid_requests \
  --from-beginning \
  --max-messages 3
```

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
  --topic bid_requests \
  --from-beginning \
  --max-messages 5
```

Pipe through `python3` for pretty-printed JSON:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic bid_requests \
  --from-beginning \
  --max-messages 1 | python3 -m json.tool
```

Check topic offsets (total message count per partition):

```bash
docker compose exec kafka /opt/kafka/bin/kafka-get-offsets.sh \
  --bootstrap-server localhost:9092 \
  --topic bid_requests
```

Tail new messages in real time (Ctrl+C to stop):

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic bid_requests
```

### 5. Stop

```bash
docker compose down
```

## Local Development (without Docker for the generator)

You can run the mock data generator outside Docker while keeping Kafka and the other infrastructure services in Docker.

### 1. Start infrastructure services only

```bash
docker compose up kafka minio iceberg-rest -d
```

### 2. Run the setup script

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

## Configuration

### Mock Data Generator

| Variable | Default | Description |
|---|---|---|
| `KAFKA_BOOTSTRAP_SERVERS` | `kafka:9092` (Docker) / `localhost:29092` (local) | Kafka broker address |
| `EVENTS_PER_SECOND` | `10` | Target event throughput |
| `TOPIC_BID_REQUESTS` | `bid_requests` | Kafka topic name |

### MinIO Console

Access the MinIO web console at [http://localhost:9001](http://localhost:9001) with credentials `admin` / `password`.

### Iceberg REST Catalog

The catalog API is available at [http://localhost:8181](http://localhost:8181). List tables:

```bash
curl -s http://localhost:8181/v1/namespaces/db/tables | python3 -m json.tool
```

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
  scripts/
    setup.sh                       # Initialize topics, bucket, tables
    run-local.sh                   # Run generator in local .venv
```
