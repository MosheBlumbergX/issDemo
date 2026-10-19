"""Connection settings, from the environment or from .env.app next to this file.

On the AWS host, the boot script writes .env.app from Secrets Manager.
"""
import os
from pathlib import Path

ENV_FILE = Path(__file__).with_name(".env.app")


def _load_env_file() -> None:
    if "BOOTSTRAP_SERVERS" in os.environ:
        return
    if not ENV_FILE.exists():
        raise SystemExit(f"Set BOOTSTRAP_SERVERS etc. in the environment or in {ENV_FILE}.")
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key, value)


_load_env_file()

TOPIC_POSITION = "iss_position"
TOPIC_TELEMETRY = "iss_telemetry"
TOPIC_STATS = "iss_stats"
TOPIC_EVENTS = "iss_events"
TOPIC_DISTANCE = "iss_distance"
TOPIC_SATELLITES = "sat_positions"
TOPIC_PROXIMITY = "iss_proximity"

# The satellite layer (Terraform variable satellites_enabled); the rest of the demo runs without it.
SATELLITES_ENABLED = os.environ.get("SATELLITES_ENABLED", "true").lower() == "true"


def kafka_conf() -> dict:
    return {
        "bootstrap.servers": os.environ["BOOTSTRAP_SERVERS"],
        "security.protocol": "SASL_SSL",
        "sasl.mechanisms": "PLAIN",
        "sasl.username": os.environ["KAFKA_API_KEY"],
        "sasl.password": os.environ["KAFKA_API_SECRET"],
    }


def schema_registry_conf() -> dict:
    return {
        "url": os.environ["SCHEMA_REGISTRY_URL"],
        "basic.auth.user.info": f"{os.environ['SCHEMA_REGISTRY_API_KEY']}:{os.environ['SCHEMA_REGISTRY_API_SECRET']}",
    }
