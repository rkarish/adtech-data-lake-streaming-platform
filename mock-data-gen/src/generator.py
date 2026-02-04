import json
import logging
import time

from kafka import KafkaProducer

from src.config import config
from src.schemas import generate_bid_request

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)


def create_producer() -> KafkaProducer:
    """Create a KafkaProducer with exponential backoff retry on connection failure."""
    delay = 1.0
    max_delay = 30.0
    max_retries = 10

    for attempt in range(1, max_retries + 1):
        try:
            producer = KafkaProducer(
                bootstrap_servers=config.kafka_bootstrap_servers,
                value_serializer=lambda v: json.dumps(v).encode("utf-8"),
                key_serializer=lambda k: k.encode("utf-8"),
            )
            logger.info(
                "Connected to Kafka at %s", config.kafka_bootstrap_servers
            )
            return producer
        except Exception as exc:
            if attempt == max_retries:
                logger.error(
                    "Failed to connect to Kafka after %d attempts", max_retries
                )
                raise
            logger.warning(
                "Kafka connection attempt %d/%d failed: %s. "
                "Retrying in %.1fs...",
                attempt,
                max_retries,
                exc,
                delay,
            )
            time.sleep(delay)
            delay = min(delay * 2, max_delay)

    # Unreachable, but satisfies type checkers
    raise RuntimeError("Failed to connect to Kafka")


def main() -> None:
    """Main producer loop with rate-limited event generation."""
    producer = create_producer()
    topic = config.topic_bid_requests
    eps = config.events_per_second
    interval = 1.0 / eps

    logger.info(
        "Starting bid request generator: %d events/sec to topic '%s'",
        eps,
        topic,
    )

    count = 0
    try:
        next_send = time.monotonic()
        while True:
            now = time.monotonic()
            if now < next_send:
                time.sleep(next_send - now)

            event = generate_bid_request()
            producer.send(topic, key=event["id"], value=event)
            count += 1

            if count % 100 == 0:
                producer.flush()
                logger.info("Produced %d bid requests", count)

            next_send += interval
    except KeyboardInterrupt:
        logger.info("Shutting down. Produced %d bid requests total.", count)
    finally:
        producer.flush()
        producer.close()
        logger.info("Producer closed.")


if __name__ == "__main__":
    main()
