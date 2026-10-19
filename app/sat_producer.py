"""Propagates the satellites that share the ISS's altitude and produces their positions to Kafka.

Every second it computes where each tracked satellite is (SGP4 on CelesTrak's orbital
elements) and writes one Avro record per satellite to `sat_positions`, stamped with the
whole second so Flink can pair it with the ISS fix from the same second. As with
`iss_position`, the table and its schema come from a Flink CREATE TABLE statement.
"""
import signal
import sys
import time
from datetime import datetime, timezone

import numpy as np
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import MessageField, SerializationContext

import config
import orbits

RELOAD_SECONDS = 600  # orbits.load_catalog() only downloads once the cache is 2 h old
RETRY_SECONDS = 120   # without a catalog, check again (orbits limits actual CelesTrak requests)

running = True


def stop(*_):
    global running
    running = False


def load_fleet() -> orbits.Fleet:
    while running:
        try:
            fleet, _iss = orbits.tracked_fleet()
            print(f"tracking {len(fleet)} satellites within {orbits.BAND_MARGIN_KM:.0f} km of the ISS's altitude")
            return fleet
        except Exception as exc:  # network, CelesTrak format change: keep the service up
            print(f"catalog load failed, retrying in {RETRY_SECONDS}s: {exc}", file=sys.stderr)
            time.sleep(RETRY_SECONDS)
    sys.exit(0)


def main() -> None:
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    sr = SchemaRegistryClient(config.schema_registry_conf())
    schema = sr.get_latest_version(f"{config.TOPIC_SATELLITES}-value").schema
    serializer = AvroSerializer(
        sr, schema.schema_str, conf={"auto.register.schemas": False, "use.latest.version": True}
    )
    producer = Producer({
        **config.kafka_conf(),
        "linger.ms": 50,
        "acks": "all",
        "compression.type": "zstd",
        "queue.buffering.max.messages": 500000,
    })
    ctx = SerializationContext(config.TOPIC_SATELLITES, MessageField.VALUE)

    def on_delivery(err, msg):
        if err:
            print(f"delivery failed: {err}", file=sys.stderr)

    fleet = load_fleet()
    loaded = time.monotonic()
    print(f"Producing satellite positions to '{config.TOPIC_SATELLITES}'. Ctrl+C to stop.")
    second = int(time.time()) + 1
    while running:
        time.sleep(max(0.0, second - time.time()))
        if time.monotonic() - loaded > RELOAD_SECONDS:
            try:
                fleet, _iss = orbits.tracked_fleet()
            except Exception as exc:
                print(f"catalog reload failed, keeping the current one: {exc}", file=sys.stderr)
            loaded = time.monotonic()

        lat, lon, alt, ok = fleet.geodetic(second)
        event_time = datetime.fromtimestamp(second, tz=timezone.utc)
        for i in np.flatnonzero(ok):
            record = {
                "norad_id": fleet.ids[i],
                "name": fleet.names[i],
                "latitude": float(lat[i]),
                "longitude": float(lon[i]),
                "altitude_km": float(alt[i]),
                "event_time": event_time,
            }
            while True:
                try:
                    producer.produce(
                        config.TOPIC_SATELLITES,
                        value=serializer(record, ctx),
                        timestamp=second * 1000,
                        on_delivery=on_delivery,
                    )
                    break
                except BufferError:  # local queue full: let librdkafka drain it
                    producer.poll(0.1)
        producer.poll(0)
        if second % 60 == 0:
            print(f"{event_time:%H:%M:%S}  {int(ok.sum())} positions/s")

        second += 1
        if time.time() > second + 2:  # fell behind (laptop sleep, slow host): skip ahead
            print(f"behind by {time.time() - second:.0f}s, skipping ahead", file=sys.stderr)
            second = int(time.time()) + 1

    producer.flush(10)
    print("stopped")


if __name__ == "__main__":
    main()
