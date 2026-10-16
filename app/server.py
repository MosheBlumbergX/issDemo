"""Dashboard backend: consumes the Flink output topics and streams them to the browser (SSE).

On start it rewinds each topic (one orbit of telemetry, a day of events) so the UI
has a trail and a flight log immediately, then follows live.
"""
import asyncio
import json
import os
import threading
import time
import uuid
from collections import deque
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
from confluent_kafka import Consumer, TopicPartition
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer
from confluent_kafka.serialization import MessageField, SerializationContext
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles

import config

LOOKBACK_SECONDS = {
    config.TOPIC_POSITION: 5 * 60,
    config.TOPIC_TELEMETRY: 95 * 60,  # roughly one orbit, for the trail
    config.TOPIC_STATS: 30 * 60,
    config.TOPIC_EVENTS: 24 * 3600,
    config.TOPIC_DISTANCE: 5 * 60,
}
TLE_URL = "https://api.wheretheiss.at/v1/satellites/25544/tles"
TLE_TTL_SECONDS = 3600

# Fields of iss_telemetry the trail/sparklines need (keeps snapshots small).
TRAIL_FIELDS = ("t", "latitude", "longitude", "altitude_km", "velocity_kmh", "sunlit")


def _jsonable(value):
    if isinstance(value, datetime):
        if value.tzinfo is None:  # Flink window bounds are local-timestamp (UTC here)
            value = value.replace(tzinfo=timezone.utc)
        return int(value.timestamp() * 1000)
    return value


class Hub:
    """Holds recent state and fans messages out to connected browsers."""

    def __init__(self) -> None:
        self.loop: asyncio.AbstractEventLoop | None = None
        self.clients: set[asyncio.Queue] = set()
        self.lock = threading.Lock()
        self.trail: deque = deque(maxlen=6000)
        self.stats: deque = deque(maxlen=200)
        self.events: deque = deque(maxlen=300)
        self.latest_position: dict | None = None
        self.latest_telemetry: dict | None = None
        self.latest_distance: dict | None = None
        self.counts = {t: 0 for t in LOOKBACK_SECONDS}
        self.arrivals = {t: deque(maxlen=2000) for t in LOOKBACK_SECONDS}
        self.caught_up = False

    def snapshot(self) -> dict:
        with self.lock:
            return {
                "trail": list(self.trail),
                "stats": list(self.stats),
                "events": list(self.events),
                "position": self.latest_position,
                "telemetry": self.latest_telemetry,
                "distance": self.latest_distance,
                "console_url": os.environ.get("CONSOLE_URL"),
            }

    def record(self, topic: str, row: dict, live: bool) -> None:
        with self.lock:
            self.counts[topic] += 1
            if live:
                self.arrivals[topic].append(time.time())
            if topic == config.TOPIC_POSITION:
                self.latest_position = row
            elif topic == config.TOPIC_TELEMETRY:
                self.latest_telemetry = row
                self.trail.append({k: row.get(k) for k in TRAIL_FIELDS})
            elif topic == config.TOPIC_STATS:
                self.stats.append(row)
            elif topic == config.TOPIC_EVENTS:
                self.events.append(row)
            elif topic == config.TOPIC_DISTANCE:
                self.latest_distance = row
        if live:
            self.publish(topic, row)

    def metrics(self) -> dict:
        now = time.time()
        with self.lock:
            rates = {t: sum(1 for a in arr if now - a <= 30) / 30 for t, arr in self.arrivals.items()}
            lag_ms = None
            if self.latest_telemetry:
                lag_ms = int(now * 1000) - self.latest_telemetry["t"]
            return {"rates": rates, "counts": dict(self.counts), "telemetry_lag_ms": lag_ms}

    def publish(self, kind: str, data) -> None:
        if not self.loop:
            return
        payload = f"event: {kind}\ndata: {json.dumps(data)}\n\n"
        self.loop.call_soon_threadsafe(self._fanout, payload)

    def _fanout(self, payload: str) -> None:
        for q in list(self.clients):
            if q.full():  # slow client: drop the oldest message rather than block
                q.get_nowait()
            q.put_nowait(payload)


hub = Hub()
stop_event = threading.Event()


def consume_loop() -> None:
    sr = SchemaRegistryClient(config.schema_registry_conf())
    deserializer = AvroDeserializer(sr)
    consumer = Consumer(
        {
            **config.kafka_conf(),
            "group.id": f"iss-dashboard-{uuid.uuid4().hex[:8]}",
            "auto.offset.reset": "latest",
            "enable.auto.commit": False,
            # Flink writes exactly-once and commits roughly once a minute; reading
            # uncommitted shows each result within seconds, which suits a live display.
            "isolation.level": "read_uncommitted",
        }
    )

    # Partition -> offset we must reach before the replay counts as done.
    replay_targets: dict[tuple[str, int], int] = {}
    assigned = threading.Event()

    def on_assign(c, partitions):
        now_ms = int(time.time() * 1000)
        wanted = [TopicPartition(p.topic, p.partition, now_ms - LOOKBACK_SECONDS[p.topic] * 1000) for p in partitions]
        resolved = c.offsets_for_times(wanted, timeout=10)
        for p in resolved:
            _low, high = c.get_watermark_offsets(p, timeout=10)
            if p.offset >= 0 and p.offset < high:  # -1: nothing that recent, start at the end
                replay_targets[(p.topic, p.partition)] = high
        c.assign([TopicPartition(p.topic, p.partition, p.offset if p.offset >= 0 else -1) for p in resolved])
        assigned.set()

    def mark_caught_up():
        hub.caught_up = True
        hub.publish("ready", hub.snapshot())

    consumer.subscribe(list(LOOKBACK_SECONDS), on_assign=on_assign)
    try:
        while not stop_event.is_set():
            msg = consumer.poll(0.5)
            if not hub.caught_up and assigned.is_set():
                # Compare positions, not message offsets: transaction markers occupy offsets too.
                for tp in consumer.position([TopicPartition(t, p) for t, p in replay_targets]):
                    if tp.offset >= replay_targets[(tp.topic, tp.partition)]:
                        del replay_targets[(tp.topic, tp.partition)]
                if not replay_targets:
                    mark_caught_up()
            if msg is None:
                continue
            if msg.error():
                print(f"consumer error: {msg.error()}")
                continue
            row = deserializer(msg.value(), SerializationContext(msg.topic(), MessageField.VALUE))
            if row is not None:
                row = {k: _jsonable(v) for k, v in row.items()}
                if "event_time" in row:
                    row["t"] = row.pop("event_time")
                hub.record(msg.topic(), row, live=hub.caught_up)
    finally:
        consumer.close()


async def metrics_loop() -> None:
    while True:
        await asyncio.sleep(2)
        hub.publish("metrics", hub.metrics())


@asynccontextmanager
async def lifespan(_app: FastAPI):
    hub.loop = asyncio.get_running_loop()
    thread = threading.Thread(target=consume_loop, daemon=True)
    thread.start()
    task = asyncio.create_task(metrics_loop())
    yield
    task.cancel()
    stop_event.set()
    thread.join(timeout=5)


app = FastAPI(lifespan=lifespan)
_tle_cache: dict = {"at": 0.0, "data": None}


@app.get("/api/stream")
async def stream(request: Request):
    queue: asyncio.Queue = asyncio.Queue(maxsize=2000)
    hub.clients.add(queue)

    async def gen():
        try:
            yield f"event: snapshot\ndata: {json.dumps(hub.snapshot())}\n\n"
            while not await request.is_disconnected():
                try:
                    yield await asyncio.wait_for(queue.get(), timeout=15)
                except asyncio.TimeoutError:
                    yield ": keepalive\n\n"
        finally:
            hub.clients.discard(queue)

    return StreamingResponse(gen(), media_type="text/event-stream", headers={"Cache-Control": "no-cache"})


@app.get("/api/tle")
async def tle():
    if time.time() - _tle_cache["at"] > TLE_TTL_SECONDS or not _tle_cache["data"]:
        async with httpx.AsyncClient(timeout=5) as http:
            resp = await http.get(TLE_URL)
            resp.raise_for_status()
            data = resp.json()
        _tle_cache.update(at=time.time(), data={"line1": data["line1"], "line2": data["line2"]})
    return JSONResponse(_tle_cache["data"])


@app.get("/api/health")
async def health():
    return {"caught_up": hub.caught_up, "clients": len(hub.clients), **hub.metrics()}


app.mount("/", StaticFiles(directory=Path(__file__).with_name("static"), html=True), name="static")
