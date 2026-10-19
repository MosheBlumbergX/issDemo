"""Satellite catalog from CelesTrak and vectorised SGP4 propagation.

Shared by the satellite producer (positions every second) and the dashboard server
(the satellite layer on the globe and the close-approach forecast). The catalog is
cached on disk so both processes together download it at most once per refresh;
CelesTrak updates it every two hours and blocks clients that poll faster.
"""
import fcntl
import json
import math
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
import numpy as np
from sgp4 import omm
from sgp4.api import Satrec, SatrecArray

CATALOG_URL = "https://celestrak.org/NORAD/elements/gp.php?GROUP=active&FORMAT=json"
CACHE_FILE = Path(__file__).with_name(".cache") / "celestrak-active.json"
REFRESH_SECONDS = 2 * 3600
ISS_NORAD_ID = 25544

MU_KM3_S2 = 398600.4418
WGS84_A_KM = 6378.137
WGS84_E2 = 6.69437999014e-3

# Only satellites whose orbit crosses the ISS's altitude range, widened by this margin,
# are tracked: nothing else can come closer than the margin. Set it a little above the
# close-approach radius. It also decides the volume: the default takes in the big
# Starlink shell at ~465 km (about 6,000 satellites); at 35 km it is under 1,000.
BAND_MARGIN_KM = float(os.environ.get("SAT_BAND_MARGIN_KM", 45))
MAX_ELEMENT_AGE_DAYS = 10  # older elements drift by tens of km a day


def load_catalog() -> list[dict]:
    """The active-satellite catalog (CelesTrak OMM JSON), from the cache when fresh."""
    CACHE_FILE.parent.mkdir(exist_ok=True)
    # Both processes start together on boot; the lock makes the second one wait and
    # then read what the first one downloaded.
    with open(CACHE_FILE.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if CACHE_FILE.exists() and time.time() - CACHE_FILE.stat().st_mtime < REFRESH_SECONDS:
            return json.loads(CACHE_FILE.read_text())
        try:
            resp = httpx.get(CATALOG_URL, timeout=30, headers={"User-Agent": "confluent-iss-demo"})
            resp.raise_for_status()
            catalog = resp.json()
            if not isinstance(catalog, list) or not catalog:
                raise ValueError("empty catalog")
        except (httpx.HTTPError, ValueError) as exc:
            if CACHE_FILE.exists():  # keep going on the old elements; they stay usable for days
                print(f"catalog refresh failed, using cached copy: {exc}", file=sys.stderr)
                return json.loads(CACHE_FILE.read_text())
            raise
        tmp = CACHE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(catalog))
        tmp.replace(CACHE_FILE)
        return catalog


def perigee_apogee_km(o: dict) -> tuple[float, float]:
    n = float(o["MEAN_MOTION"]) * 2 * math.pi / 86400  # rev/day -> rad/s
    a = (MU_KM3_S2 / n**2) ** (1 / 3)
    e = float(o["ECCENTRICITY"])
    return a * (1 - e) - WGS84_A_KM, a * (1 + e) - WGS84_A_KM


def satrec(o: dict) -> Satrec:
    sat = Satrec()
    omm.initialize(sat, o)
    return sat


def jd_parts(unix_s: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    days = np.asarray(unix_s, dtype=float) / 86400.0
    whole = np.floor(days)
    return whole + 2440587.5, days - whole


def gmst_rad(unix_s: np.ndarray) -> np.ndarray:
    """Greenwich mean sidereal time (IAU 1982, as used by SGP4)."""
    jd, fr = jd_parts(unix_s)
    t = (jd - 2451545.0 + fr) / 36525.0
    sec = 67310.54841 + (876600.0 * 3600 + 8640184.812866) * t + 0.093104 * t**2 - 6.2e-6 * t**3
    return np.radians(np.mod(sec, 86400.0) / 240.0)


def teme_to_ecef(r: np.ndarray, unix_s: np.ndarray) -> np.ndarray:
    """Rotate TEME positions (..., n_times, 3) into Earth-fixed coordinates."""
    g = gmst_rad(unix_s)
    c, s = np.cos(g), np.sin(g)
    x, y, z = r[..., 0], r[..., 1], r[..., 2]
    return np.stack([c * x + s * y, -s * x + c * y, z], axis=-1)


def ecef_to_geodetic(p: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """WGS84 latitude and longitude in degrees, height in km."""
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    lon = np.arctan2(y, x)
    rho = np.hypot(x, y)
    lat = np.arctan2(z, rho * (1 - WGS84_E2))
    for _ in range(4):
        n = WGS84_A_KM / np.sqrt(1 - WGS84_E2 * np.sin(lat) ** 2)
        h = rho / np.cos(lat) - n
        lat = np.arctan2(z, rho * (1 - WGS84_E2 * n / (n + h)))
    n = WGS84_A_KM / np.sqrt(1 - WGS84_E2 * np.sin(lat) ** 2)
    return np.degrees(lat), np.degrees(lon), rho / np.cos(lat) - n


class Fleet:
    """A set of satellites propagated together."""

    def __init__(self, sats: list[dict]) -> None:
        self.sats = sats
        self.ids = [int(o["NORAD_CAT_ID"]) for o in sats]
        self.names = [str(o["OBJECT_NAME"]).strip() for o in sats]
        self._array = SatrecArray([satrec(o) for o in sats]) if sats else None

    def __len__(self) -> int:
        return len(self.sats)

    def ecef(self, unix_s) -> tuple[np.ndarray, np.ndarray]:
        """Earth-fixed positions, shape (n_sats, n_times, 3) in km, and a validity mask."""
        unix_s = np.atleast_1d(np.asarray(unix_s, dtype=float))
        jd, fr = jd_parts(unix_s)
        err, r, _v = self._array.sgp4(jd, fr)
        return teme_to_ecef(r, unix_s), err == 0

    def geodetic(self, unix_s: float) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """Latitude, longitude, altitude and validity for every satellite at one instant."""
        p, ok = self.ecef(unix_s)
        lat, lon, alt = ecef_to_geodetic(p[:, 0])
        return lat, lon, alt, ok[:, 0]


def tracked_fleet() -> tuple[Fleet, dict | None]:
    """The satellites the producer streams, and the ISS's own elements."""
    catalog = load_catalog()
    return Fleet(select_neighbours(catalog)), iss_elements(catalog)


def forecast(hours: float, radius_km: float) -> list[dict]:
    """Close approaches over the next few hours (runs in a worker process)."""
    fleet, iss = tracked_fleet()
    # Whole seconds, like the ISS fixes and satellite positions Flink compares.
    return close_approaches(fleet, iss, float(int(time.time())), hours, radius_km) if iss else []


def iss_elements(catalog: list[dict]) -> dict | None:
    return next((o for o in catalog if int(o["NORAD_CAT_ID"]) == ISS_NORAD_ID), None)


def select_neighbours(catalog: list[dict], now: float | None = None) -> list[dict]:
    """Satellites whose orbits cross the ISS altitude band, minus anything docked to it."""
    now = time.time() if now is None else now
    iss = iss_elements(catalog)
    low, high = perigee_apogee_km(iss) if iss else (400.0, 430.0)
    low, high = low - BAND_MARGIN_KM, high + BAND_MARGIN_KM
    picked = []
    for o in catalog:
        if int(o["NORAD_CAT_ID"]) == ISS_NORAD_ID:
            continue
        try:
            perigee, apogee = perigee_apogee_km(o)
            age_days = (now - _epoch_unix(o["EPOCH"])) / 86400
        except (KeyError, ValueError, ZeroDivisionError):
            continue
        if perigee <= high and apogee >= low and age_days <= MAX_ELEMENT_AGE_DAYS:
            picked.append(o)

    # Visiting spacecraft docked to the station (Soyuz, Progress, Dragon...) have their own
    # catalog entries and would sit at zero distance forever. Drop anything that stays close.
    if iss and picked:
        times = now + np.arange(0, 93 * 60, 600)
        iss_p, _ = Fleet([iss]).ecef(times)
        sat_p, ok = Fleet(picked).ecef(times)
        far = (np.linalg.norm(sat_p - iss_p, axis=-1) > 50).any(axis=1) & ok.all(axis=1)
        picked = [o for o, keep in zip(picked, far) if keep]
    return picked


def _epoch_unix(epoch: str) -> float:
    return datetime.fromisoformat(epoch).replace(tzinfo=timezone.utc).timestamp()


def close_approaches(
    fleet: Fleet, iss: dict, start: float, hours: float, radius_km: float, coarse_step_s: int = 20
) -> list[dict]:
    """Predicted closest approaches to the ISS under radius_km, soonest first.

    Screens every satellite on a coarse time grid, then refines each candidate pass
    second by second. Relative speeds reach ~15 km/s, so the coarse threshold is
    widened by the distance two objects can close in one step.
    """
    iss_fleet = Fleet([iss])
    times = start + np.arange(0, hours * 3600 + coarse_step_s, coarse_step_s)
    screen_km = radius_km + 15 * coarse_step_s
    candidates: dict[int, set[int]] = {}
    for lo in range(0, len(times), 90):  # chunks keep memory flat on a small instance
        chunk = times[lo : lo + 90]
        iss_p, _ = iss_fleet.ecef(chunk)
        sat_p, ok = fleet.ecef(chunk)
        d = np.linalg.norm(sat_p - iss_p, axis=-1)
        for s, k in zip(*np.nonzero((d < screen_km) & ok)):
            candidates.setdefault(int(s), set()).add(lo + int(k))

    found = []
    for s, steps in candidates.items():
        for first, last in _runs(sorted(steps)):
            fine = np.arange(times[max(first - 1, 0)], times[min(last + 1, len(times) - 1)] + 1, 1.0)
            iss_p, _ = iss_fleet.ecef(fine)
            sat_p, ok = Fleet([fleet.sats[s]]).ecef(fine)
            d = np.where(ok[0], np.linalg.norm(sat_p[0] - iss_p[0], axis=-1), np.inf)
            k = int(np.argmin(d))
            if d[k] < radius_km and 0 < k < len(fine) - 1:  # a true minimum, not a window edge
                lat, lon, alt = ecef_to_geodetic(sat_p[0, k])
                _, _, iss_alt = ecef_to_geodetic(iss_p[0, k])
                found.append({
                    "t": int(fine[k] * 1000),
                    "norad_id": fleet.ids[s],
                    "name": fleet.names[s],
                    "distance_km": round(float(d[k]), 1),
                    "altitude_km": round(float(alt), 1),
                    "iss_altitude_km": round(float(iss_alt), 1),
                    "latitude": round(float(lat), 3),
                    "longitude": round(float(lon), 3),
                })
    return sorted(found, key=lambda a: a["t"])


def _runs(steps: list[int]):
    """Group sorted step indices into runs of consecutive values."""
    first = prev = steps[0]
    for k in steps[1:]:
        if k != prev + 1:
            yield first, prev
            first = k
        prev = k
    yield first, prev
