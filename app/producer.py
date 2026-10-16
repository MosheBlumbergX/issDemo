"""Polls the live ISS position and produces it to Kafka (Avro, schema owned by Flink).

The `iss_position` table and its Avro schema are created by Terraform via a Flink
CREATE TABLE statement; this producer fetches that schema from Schema Registry and
never registers its own.
"""
import signal
import sys
import time
from datetime import datetime, timezone

import httpx
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import MessageField, SerializationContext

import config

ISS_URL = "https://api.wheretheiss.at/v1/satellites/25544"
POLL_SECONDS = 1.0  # wheretheiss.at allows roughly one request per second

running = True


def stop(*_):
    global running
    running = False


def to_record(raw: dict) -> dict:
    return {
        "satellite_id": int(raw["id"]),
        "latitude": float(raw["latitude"]),
        "longitude": float(raw["longitude"]),
        "altitude_km": float(raw["altitude"]),
        "velocity_kmh": float(raw["velocity"]),
        "visibility": str(raw["visibility"]),
        "footprint_km": float(raw["footprint"]),
        "solar_lat": float(raw["solar_lat"]),
        "solar_lon": float(raw["solar_lon"]),
        "source": "wheretheiss.at",
        "event_time": datetime.fromtimestamp(raw["timestamp"], tz=timezone.utc),
    }


def main() -> None:
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    sr = SchemaRegistryClient(config.schema_registry_conf())
    schema = sr.get_latest_version(f"{config.TOPIC_POSITION}-value").schema
    serializer = AvroSerializer(
        sr, schema.schema_str, conf={"auto.register.schemas": False, "use.latest.version": True}
    )
    producer = Producer({**config.kafka_conf(), "linger.ms": 20, "acks": "all"})
    ctx = SerializationContext(config.TOPIC_POSITION, MessageField.VALUE)

    def on_delivery(err, msg):
        if err:
            print(f"delivery failed: {err}", file=sys.stderr)

    print(f"Producing ISS positions to '{config.TOPIC_POSITION}'. Ctrl+C to stop.")
    last_ts = None
    backoff = POLL_SECONDS
    with httpx.Client(timeout=5.0, headers={"User-Agent": "confluent-iss-demo"}) as http:
        while running:
            started = time.monotonic()
            try:
                resp = http.get(ISS_URL)
                if resp.status_code == 429:
                    backoff = min(backoff * 2, 30)
                    print(f"rate limited, backing off {backoff:.0f}s", file=sys.stderr)
                    time.sleep(backoff)
                    continue
                resp.raise_for_status()
                backoff = POLL_SECONDS
                raw = resp.json()
                if raw["timestamp"] != last_ts:  # API has 1 s resolution; skip duplicates
                    last_ts = raw["timestamp"]
                    record = to_record(raw)
                    producer.produce(
                        config.TOPIC_POSITION,
                        value=serializer(record, ctx),
                        timestamp=raw["timestamp"] * 1000,
                        on_delivery=on_delivery,
                    )
                    print(
                        f"{record['event_time']:%H:%M:%S}  lat {record['latitude']:8.3f}  "
                        f"lon {record['longitude']:9.3f}  alt {record['altitude_km']:6.1f} km  "
                        f"{record['velocity_kmh']:9,.0f} km/h  {record['visibility']}"
                    )
            except (httpx.HTTPError, KeyError, ValueError) as exc:
                print(f"fetch failed: {exc}", file=sys.stderr)
            producer.poll(0)
            time.sleep(max(0.0, POLL_SECONDS - (time.monotonic() - started)))

    producer.flush(10)
    print("stopped")


if __name__ == "__main__":
    main()
