import * as THREE from "https://esm.sh/three@0.186.1";
import Globe from "https://esm.sh/globe.gl@2.46.2?deps=three@0.186.1";
import * as satellite from "https://esm.sh/satellite.js@7.1.0";

const EARTH_RADIUS_KM = 6371;
const AMBER = "#ffb547";
const ICE = "#8fd3ff";
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const $ = (id) => document.getElementById(id);
const fmt = (n, digits = 0) =>
  n == null || Number.isNaN(n) ? "-" : n.toLocaleString(undefined, { minimumFractionDigits: digits, maximumFractionDigits: digits });
const clock = (ms) => new Date(ms).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });

const state = {
  trail: [],
  stats: [],
  events: [],
  position: null,
  telemetry: null,
  tle: null,
  follow: true,
  distance: null,
  lastTrailDraw: 0,
  satellitesEnabled: false,
  satellites: [],    // tracked catalog: { id, name, satrec }
  catalogPoints: [], // their positions, propagated in the browser
  neighbours: null,  // Flink's iss_proximity, one second's set: { t, sats }
  forecast: null,
};

// ---------------------------------------------------------------------------
// Globe with a real day/night terminator, driven by the subsolar point in the feed
// ---------------------------------------------------------------------------
const loader = new THREE.TextureLoader();
const dayNight = new THREE.ShaderMaterial({
  uniforms: {
    dayTexture: { value: loader.load("img/earth-blue-marble.jpg") },
    nightTexture: { value: loader.load("img/earth-night.jpg") },
    sunDirection: { value: new THREE.Vector3(1, 0, 0) },
  },
  vertexShader: `
    varying vec3 vNormalW;
    varying vec2 vUv;
    void main() {
      vNormalW = normalize(mat3(modelMatrix) * normal);
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }`,
  fragmentShader: `
    uniform sampler2D dayTexture;
    uniform sampler2D nightTexture;
    uniform vec3 sunDirection;
    varying vec3 vNormalW;
    varying vec2 vUv;
    void main() {
      float light = dot(normalize(vNormalW), normalize(sunDirection));
      vec3 day = texture2D(dayTexture, vUv).rgb * 0.92;
      vec3 night = texture2D(nightTexture, vUv).rgb * 1.35 + vec3(0.0, 0.012, 0.03);
      float mixAmt = smoothstep(-0.12, 0.14, light);
      vec3 color = mix(night, day, mixAmt);
      // a faint warm band along the terminator
      color += vec3(1.0, 0.55, 0.2) * 0.10 * (1.0 - abs(mixAmt * 2.0 - 1.0));
      gl_FragColor = vec4(color, 1.0);
    }`,
});

const issIcon = `
<svg viewBox="0 0 64 64" aria-hidden="true">
  <g fill="none" stroke="${AMBER}" stroke-width="2">
    <rect x="4" y="14" width="12" height="36" fill="rgba(255,181,71,0.25)"/>
    <rect x="48" y="14" width="12" height="36" fill="rgba(255,181,71,0.25)"/>
    <line x1="16" y1="32" x2="48" y2="32"/>
    <rect x="25" y="25" width="14" height="14" rx="2" fill="#061224"/>
    <line x1="32" y1="18" x2="32" y2="46"/>
  </g>
</svg>`;

const issDatum = { lat: 0, lng: 0, alt: 0.067 };
const issEl = document.createElement("div");
issEl.className = "iss-marker";
issEl.innerHTML = `${issIcon}<span>ISS</span>`;

const globeEl = $("globe");
const globe = new Globe(globeEl, { rendererConfig: { antialias: true, alpha: false } })
  .backgroundImageUrl("img/night-sky.png")
  .globeMaterial(dayNight)
  .showAtmosphere(true)
  .atmosphereColor("#7fb8ff")
  .atmosphereAltitude(0.16)
  // ISS marker
  .htmlElementsData([issDatum])
  .htmlLat("lat").htmlLng("lng").htmlAltitude("alt")
  .htmlElement(() => issEl)
  .htmlTransitionDuration(1000)
  // trail segments + predicted orbit
  .pathPointLat((p) => p[0]).pathPointLng((p) => p[1]).pathPointAlt((p) => p[2])
  .pathColor((d) => d.color)
  .pathStroke((d) => d.stroke)
  .pathDashLength((d) => (d.kind === "forecast" ? 0.012 : 1))
  .pathDashGap((d) => (d.kind === "forecast" ? 0.008 : 0))
  .pathDashAnimateTime((d) => (d.kind === "forecast" && !reducedMotion ? 60000 : 0))
  .pathTransitionDuration(0)
  // visibility footprint under the station + flyover pulses
  .ringLat("lat").ringLng("lng").ringAltitude(0.002)
  .ringColor((d) => (t) =>
    d.kind === "flyover" ? `rgba(143,211,255,${1 - t})`
    : d.kind === "conjunction" ? `rgba(255,181,71,${1 - t})`
    : `rgba(255,181,71,${0.55 * (1 - t)})`)
  .ringMaxRadius("radius")
  .ringPropagationSpeed((d) => (d.kind === "footprint" ? 5 : 2))
  .ringRepeatPeriod((d) => (reducedMotion ? 0 : d.kind === "footprint" ? 2200 : 900))
  // event markers, and names of the nearest satellites
  .labelLat("lat").labelLng("lng").labelText("text")
  .labelSize((d) => d.size ?? 0.55).labelDotRadius((d) => d.dot ?? 0.35)
  .labelColor((d) => d.color)
  .labelResolution(2)
  .labelAltitude((d) => d.alt ?? 0.004)
  // satellites: the whole tracked catalog (faint) and Flink's nearby set (bright)
  .particlesList("pts")
  .particleLat("lat").particleLng("lng").particleAltitude("alt")
  .particlesSize("size")
  .particlesSizeAttenuation(false)
  .particlesColor("color");

// Hide the marker while the station is on the far side of the planet. globe.gl only
// re-checks occlusion when the camera moves, so test every frame ourselves.
globe.htmlElementVisibilityModifier(() => {});
(function occlusionLoop() {
  const p = globe.getCoords(issDatum.lat, issDatum.lng, issDatum.alt);
  const c = globe.camera().position;
  const facing = p.x * (c.x - p.x) + p.y * (c.y - p.y) + p.z * (c.z - p.z) > 0;
  issEl.style.visibility = facing ? "visible" : "hidden";
  requestAnimationFrame(occlusionLoop);
})();
globe.controls().autoRotate = false;
globe.controls().addEventListener("start", () => setFollow(false));
globe.pointOfView({ lat: 20, lng: 0, altitude: 2.4 });

function resize() {
  globe.width(globeEl.clientWidth).height(globeEl.clientHeight);
}
window.addEventListener("resize", resize);
resize();

function setSun(lat, lonEast) {
  const lng = lonEast > 180 ? lonEast - 360 : lonEast;
  const { x, y, z } = globe.getCoords(lat, lng, 0);
  dayNight.uniforms.sunDirection.value.set(x, y, z).normalize();
}

// ---------------------------------------------------------------------------
// Paths: trail (coloured by sunlight, from Flink's `sunlit`) and TLE forecast
// ---------------------------------------------------------------------------
function trailSegments() {
  const segments = [];
  let current = null;
  let prev = null;
  for (const p of state.trail) {
    const breakHere = !current || p.sunlit !== current.sunlit || (prev && p.t - prev.t > 30000);
    if (breakHere) {
      if (current && prev && p.t - prev.t <= 30000) current.points.push(toPoint(p)); // join seamlessly
      current = { sunlit: p.sunlit, points: [] };
      segments.push(current);
    }
    current.points.push(toPoint(p));
    prev = p;
  }
  return segments
    .filter((s) => s.points.length > 1)
    .map((s) => ({
      kind: "trail",
      points: s.points,
      color: s.sunlit ? AMBER : "rgba(147,169,195,0.75)",
      stroke: 1.6,
    }));
}

const toPoint = (p) => [p.latitude, p.longitude, (p.altitude_km ?? 420) / EARTH_RADIUS_KM];

function forecastPath() {
  if (!state.tle) return [];
  const satrec = satellite.twoline2satrec(state.tle.line1, state.tle.line2);
  const points = [];
  const start = Date.now();
  for (let s = 0; s <= 93 * 60; s += 30) {
    const date = new Date(start + s * 1000);
    const pv = satellite.propagate(satrec, date);
    if (!pv || !pv.position) continue;
    const geo = satellite.eciToGeodetic(pv.position, satellite.gstime(date));
    points.push([satellite.degreesLat(geo.latitude), satellite.degreesLong(geo.longitude), geo.height / EARTH_RADIUS_KM]);
  }
  return [{ kind: "forecast", points, color: ICE, stroke: 1.1 }];
}

function drawPaths() {
  state.lastTrailDraw = Date.now();
  globe.pathsData([...trailSegments(), ...forecastPath()].map((d) => ({ ...d, pts: d.points })));
}
globe.pathPoints("pts");

async function loadTle() {
  try {
    const resp = await fetch("/api/tle");
    if (resp.ok) state.tle = await resp.json();
  } catch { /* forecast is optional */ }
  drawPaths();
}

// ---------------------------------------------------------------------------
// Rings + labels
// ---------------------------------------------------------------------------
let flyoverRings = [];

function drawRings() {
  const p = state.position;
  const footprint = p
    ? [{ kind: "footprint", lat: p.latitude, lng: p.longitude, radius: (p.footprint_km || 4500) / 2 / 111.2 }]
    : [];
  const now = Date.now();
  flyoverRings = flyoverRings.filter((r) => now - r.at < 10 * 60 * 1000);
  globe.ringsData([...footprint, ...flyoverRings]);
}

function drawLabels() {
  const recent = state.events.filter((e) => e.event_type === "CITY_FLYOVER").slice(-8);
  const nearest = currentNeighbours().slice(0, 3);
  globe.labelsData([
    ...recent.map((e) => ({
      lat: e.latitude,
      lng: e.longitude,
      text: e.title.replace("Flyover: ", "").split(",")[0],
      color: "rgba(143,211,255,0.9)",
    })),
    ...nearest.map((s) => ({
      lat: s.latitude,
      lng: s.longitude,
      alt: s.altitude_km / EARTH_RADIUS_KM,
      text: `${s.name} ${fmt(s.distance_km)} km`,
      color: "rgba(232,238,246,0.85)",
      size: 0.28,
      dot: 0.15,
    })),
  ]);
}

// ---------------------------------------------------------------------------
// Satellites: the catalog is propagated here for the picture; which ones are
// near the ISS, and how near, comes from Flink (iss_proximity).
// ---------------------------------------------------------------------------
async function loadSatellites() {
  try {
    const resp = await fetch("/api/satellites");
    if (!resp.ok) return;
    const list = await resp.json();
    state.satellites = list.map((s) => ({ id: s.id, name: s.name, satrec: satellite.twoline2satrec(s.line1, s.line2) }));
    $("sat-rate").textContent = fmt(list.length); // the producer sends each one every second
    propagateCatalog();
  } catch { /* the layer is optional */ }
}

function propagateCatalog() {
  if (!state.satellites.length) return;
  // Same instant as the ISS marker, which trails real time by the pipeline lag.
  const date = new Date(state.position?.t ?? Date.now());
  const gmst = satellite.gstime(date);
  const points = [];
  for (const s of state.satellites) {
    const pv = satellite.propagate(s.satrec, date);
    if (!pv || !pv.position) continue;
    const geo = satellite.eciToGeodetic(pv.position, gmst);
    points.push({ lat: satellite.degreesLat(geo.latitude), lng: satellite.degreesLong(geo.longitude), alt: geo.height / EARTH_RADIUS_KM });
  }
  state.catalogPoints = points;
  drawSatellites();
}

// Flink's latest set, nearest first; empty once it is more than a few seconds behind the ISS.
function currentNeighbours() {
  const n = state.neighbours;
  if (!n || (state.position && state.position.t - n.t > 10000)) return [];
  return n.sats.slice().sort((a, b) => a.distance_km - b.distance_km);
}

function drawSatellites() {
  const near = currentNeighbours().map((s) => ({ lat: s.latitude, lng: s.longitude, alt: s.altitude_km / EARTH_RADIUS_KM }));
  globe.particlesData([
    { pts: state.catalogPoints, color: "#5d7898", size: 1.5 },
    { pts: near, color: ICE, size: 4 },
  ]);
}

function renderNeighbours() {
  drawSatellites();
  drawLabels();
  if (!state.neighbours) return;
  const sats = currentNeighbours();
  $("near-count").textContent = fmt(sats.length);
  $("near-name").textContent = sats.length ? sats[0].name : "None in range";
  $("near-dist").textContent = sats.length ? fmt(sats[0].distance_km) : "-";
}

function countdown(ms) {
  const min = Math.round(ms / 60000);
  if (min < 1) return "now";
  if (min < 60) return `in ${min} min`;
  return `in ${Math.floor(min / 60)} h ${min % 60} min`;
}

function renderForecast() {
  const f = state.forecast;
  if (!f) return;
  $("forecast-sub").textContent = `Predicted from orbital elements: the next ${f.hours} hours, under ${fmt(f.radius_km)} km`;
  const now = Date.now();
  const upcoming = f.approaches.filter((a) => a.t > now - 30000).slice(0, 3);
  $("forecast").replaceChildren(...upcoming.map((a) => {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.title = "Show on the globe";
    btn.innerHTML = `
      <span class="glyph" aria-hidden="true">◇</span>
      <span class="title"></span>
      <span class="time">${countdown(a.t - now)}</span>
      <span class="detail"></span>`;
    const above = a.altitude_km >= a.iss_altitude_km ? "above" : "below";
    btn.querySelector(".title").textContent = a.name;
    btn.querySelector(".detail").textContent =
      `${fmt(a.distance_km)} km from the ISS, ${fmt(Math.abs(a.altitude_km - a.iss_altitude_km))} km ${above}, at ${clock(a.t)}`;
    btn.addEventListener("click", () => {
      setFollow(false);
      globe.pointOfView({ lat: a.latitude, lng: a.longitude, altitude: 1.6 }, 1200);
    });
    li.append(btn);
    return li;
  }));
  const empty = $("forecast-empty");
  empty.hidden = upcoming.length > 0;
  empty.textContent = `None predicted under ${fmt(f.radius_km)} km in the next ${f.hours} hours`;
}

// ---------------------------------------------------------------------------
// Readouts
// ---------------------------------------------------------------------------
function renderPosition() {
  // The raw feed only moves the marker and the sun; every number shown comes from Flink.
  const p = state.position;
  if (!p) return;
  issDatum.lat = p.latitude;
  issDatum.lng = p.longitude;
  issDatum.alt = p.altitude_km / EARTH_RADIUS_KM;
  globe.htmlElementsData([issDatum]);
  if (p.solar_lat != null) setSun(p.solar_lat, p.solar_lon);
  drawRings();

  if (state.follow) {
    globe.pointOfView({ lat: p.latitude * 0.6, lng: p.longitude, altitude: globe.pointOfView().altitude }, 1000);
  }
}

const compassPoints = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"];

function renderTelemetry() {
  const t = state.telemetry;
  if (!t) return;
  $("v-kmh").textContent = fmt(t.velocity_kmh);
  $("v-mph").textContent = fmt(t.velocity_mph);
  $("v-kms").textContent = fmt(t.velocity_kms, 2);
  $("alt").textContent = fmt(t.altitude_km, 1);
  $("lat").textContent = `${fmt(Math.abs(t.latitude), 3)}° ${t.latitude >= 0 ? "N" : "S"}`;
  $("lon").textContent = `${fmt(Math.abs(t.longitude), 3)}° ${t.longitude >= 0 ? "E" : "W"}`;
  $("ground").textContent = fmt(t.ground_speed_kmh);
  if (t.heading_deg != null) {
    $("heading").textContent = `${fmt(t.heading_deg)}°`;
    $("compass-needle").style.transform = `rotate(${t.heading_deg}deg)`;
  }
  const hemisphere = t.hemisphere === "NORTH" ? "northern" : "southern";
  const heading = t.heading_deg != null ? compassPoints[Math.round(t.heading_deg / 45) % 8] : null;
  const light = t.sunlit ? "In sunlight" : "In Earth's shadow";
  $("situation").textContent = `${light}, over the ${hemisphere} hemisphere${heading ? `, heading ${heading}` : ""}`;
}

function renderDistance() {
  const d = state.distance;
  if (!d) return;
  $("dist-1h").textContent = fmt(d.distance_1h_km);
  $("dist-total").textContent = fmt(d.distance_total_km);
  if (d.tracked_since) {
    const start = new Date(d.tracked_since);
    const sameDay = start.toDateString() === new Date().toDateString();
    const since = sameDay
      ? start.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
      : start.toLocaleDateString([], { month: "short", day: "numeric" });
    $("dist-total-label").textContent = `Distance since ${since}`;
  }
}

// ---------------------------------------------------------------------------
// Sparklines (single series: title names it, crosshair + tooltip on hover)
// ---------------------------------------------------------------------------
function sparkline(figureId, series, unit, digits) {
  const plot = document.querySelector(`#${figureId} .spark-plot`);
  if (series.length < 2) {
    plot.innerHTML = `<p class="empty">Collecting data</p>`;
    return;
  }
  const w = plot.clientWidth || 290;
  const h = plot.clientHeight || 64;
  const padR = 52;
  const ys = series.map((d) => d.v);
  let min = Math.min(...ys);
  let max = Math.max(...ys);
  if (max - min < 1e-6) { min -= 1; max += 1; }
  const t0 = series[0].t;
  const t1 = series[series.length - 1].t;
  const x = (t) => ((t - t0) / Math.max(1, t1 - t0)) * (w - padR);
  const y = (v) => 4 + (1 - (v - min) / (max - min)) * (h - 10);
  const d = series.map((p, i) => `${i ? "L" : "M"}${x(p.t).toFixed(1)},${y(p.v).toFixed(1)}`).join("");
  plot.innerHTML = `
    <svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${plot.previousElementSibling.textContent}">
      <line class="baseline" x1="0" x2="${w - padR}" y1="${h - 1}" y2="${h - 1}"/>
      <path class="line" d="${d}"/>
      <text class="bound" x="${w - padR + 8}" y="${y(max) + 4}">${fmt(max, digits)}</text>
      <text class="bound" x="${w - padR + 8}" y="${y(min) + 4}">${fmt(min, digits)}</text>
      <line class="cross" y1="0" y2="${h}" visibility="hidden"/>
      <circle class="dot" r="4" visibility="hidden"/>
    </svg>
    <div class="tip" hidden></div>`;
  const svg = plot.querySelector("svg");
  const cross = svg.querySelector(".cross");
  const dot = svg.querySelector(".dot");
  const tip = plot.querySelector(".tip");
  svg.addEventListener("pointermove", (ev) => {
    const rect = svg.getBoundingClientRect();
    const px = ((ev.clientX - rect.left) / rect.width) * w;
    const tAt = t0 + (Math.min(px, w - padR) / (w - padR)) * (t1 - t0);
    let best = series[0];
    for (const p of series) if (Math.abs(p.t - tAt) < Math.abs(best.t - tAt)) best = p;
    const bx = x(best.t);
    cross.setAttribute("x1", bx); cross.setAttribute("x2", bx); cross.setAttribute("visibility", "visible");
    dot.setAttribute("cx", bx); dot.setAttribute("cy", y(best.v)); dot.setAttribute("visibility", "visible");
    tip.hidden = false;
    tip.style.left = `${(bx / w) * 100}%`;
    tip.textContent = `${fmt(best.v, digits)} ${unit} at ${clock(best.t)}`;
  });
  svg.addEventListener("pointerleave", () => {
    cross.setAttribute("visibility", "hidden");
    dot.setAttribute("visibility", "hidden");
    tip.hidden = true;
  });
}

function renderSparks() {
  const step = Math.max(1, Math.floor(state.trail.length / 300));
  sparkline(
    "spark-alt",
    state.trail.filter((_, i) => i % step === 0).map((p) => ({ t: p.t, v: p.altitude_km })),
    "km",
    1,
  );
  sparkline(
    "spark-speed",
    state.stats.filter((s) => s.avg_velocity_kmh != null).map((s) => ({ t: s.window_end, v: s.avg_velocity_kmh })),
    "km/h",
    0,
  );
}

// ---------------------------------------------------------------------------
// Flight log
// ---------------------------------------------------------------------------
const glyphs = {
  ASCENDING_NODE: "↗",
  DESCENDING_NODE: "↘",
  ORBITAL_SUNRISE: "☀",
  ORBITAL_SUNSET: "◐",
  NORTHERNMOST_POINT: "▲",
  SOUTHERNMOST_POINT: "▼",
  CITY_FLYOVER: "◎",
  ORBIT_COMPLETE: "↻",
  ECLIPSE_PASS: "●",
  CONJUNCTION: "◆",
};

function eventItem(e, fresh) {
  const li = document.createElement("li");
  li.className = `t-${e.event_type}${fresh ? " fresh" : ""}`;
  const btn = document.createElement("button");
  btn.type = "button";
  btn.title = "Show on the globe";
  btn.innerHTML = `
    <span class="glyph" aria-hidden="true">${glyphs[e.event_type] || "•"}</span>
    <span class="title"></span>
    <span class="time">${clock(e.t)}</span>
    <span class="detail"></span>`;
  btn.querySelector(".title").textContent = e.title;
  btn.querySelector(".detail").textContent = e.detail || "";
  btn.addEventListener("click", () => {
    setFollow(false);
    globe.pointOfView({ lat: e.latitude, lng: e.longitude, altitude: 1.6 }, 1200);
  });
  li.append(btn);
  return li;
}

// A replaced Flink statement replays its input and can re-emit an event; keep the latest copy.
const eventKey = (e) => `${e.event_type}|${e.title}|${e.t}`;
function dedupeEvents(events) {
  const byKey = new Map();
  for (const e of events) {
    byKey.delete(eventKey(e));
    byKey.set(eventKey(e), e);
  }
  return [...byKey.values()].sort((a, b) => a.t - b.t);
}

function renderEvents() {
  const list = $("events");
  list.replaceChildren(...state.events.slice().reverse().slice(0, 150).map((e) => eventItem(e, false)));
  $("events-empty").hidden = state.events.length > 0;
  document.querySelector('[data-topic="iss_events"] .total').textContent = fmt(state.events.length);
  drawLabels();
}

function addEvent(e) {
  if (state.events.some((x) => eventKey(x) === eventKey(e))) {
    state.events = dedupeEvents([...state.events, e]);
    renderEvents();
    return;
  }
  state.events.push(e);
  $("events").prepend(eventItem(e, true));
  $("events-empty").hidden = true;
  document.querySelector('[data-topic="iss_events"] .total').textContent = fmt(state.events.length);
  if (e.event_type === "CITY_FLYOVER") {
    flyoverRings.push({ kind: "flyover", lat: e.latitude, lng: e.longitude, radius: 6, at: Date.now() });
    drawLabels();
    queueBanner(e);
  } else if (e.event_type === "CONJUNCTION") {
    flyoverRings.push({ kind: "conjunction", lat: e.latitude, lng: e.longitude, radius: 4, at: Date.now() });
    queueBanner(e);
  }
}

// Flink commits about once a minute, so events arrive in bursts: one banner per burst.
let bannerQueue = [];
let bannerFlush;
function queueBanner(e) {
  bannerQueue.push(e);
  clearTimeout(bannerFlush);
  bannerFlush = setTimeout(() => {
    const conjunction = bannerQueue.findLast((x) => x.event_type === "CONJUNCTION");
    const cities = bannerQueue.filter((x) => x.event_type === "CITY_FLYOVER").map((x) => x.title.replace("Flyover: ", "").split(",")[0]);
    const last = bannerQueue[bannerQueue.length - 1];
    bannerQueue = [];
    if (conjunction) {
      showBanner(`${conjunction.title.replace("Close approach: ", "")} passed ${fmt(conjunction.distance_km)} km from the ISS`, "conjunction");
    } else if (cities.length === 1) {
      showBanner(`${last.title.replace("Flyover: ", "Passing ")}, ${fmt(last.distance_km)} km away`);
    } else if (cities.length > 1) {
      const recent = cities.slice(-3).reverse();
      const more = cities.length - recent.length;
      showBanner(more ? `Passing ${recent.join(", ")} and ${more} more` : `Passing ${recent.slice(0, -1).join(", ")} and ${recent.at(-1)}`);
    }
  }, 400);
}

let bannerTimer;
function showBanner(text, kind = "flyover") {
  const el = $("banner");
  if (kind !== "conjunction" && !el.hidden && el.classList.contains("conjunction")) return; // rarer; let it stay
  el.textContent = text;
  el.classList.toggle("conjunction", kind === "conjunction");
  el.hidden = false;
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => (el.hidden = true), 12000);
}

// ---------------------------------------------------------------------------
// Pipeline strip
// ---------------------------------------------------------------------------
function pulse(topic) {
  if (reducedMotion) return;
  const node = document.querySelector(`[data-topic="${topic}"]`);
  if (!node) return;
  node.classList.add("pulse");
  setTimeout(() => node.classList.remove("pulse"), 120);
}

function renderMetrics(m) {
  for (const [topic, rate] of Object.entries(m.rates)) {
    const el = document.querySelector(`[data-topic="${topic}"] .rate`);
    if (el) el.textContent = rate.toFixed(1);
  }
  if (m.telemetry_lag_ms != null) {
    const s = m.telemetry_lag_ms / 1000;
    $("lag").textContent = s < 60 ? `${s.toFixed(1)} s` : `${fmt(s / 60)} min`;
  }
}

// ---------------------------------------------------------------------------
// Follow toggle
// ---------------------------------------------------------------------------
function setFollow(on) {
  state.follow = on;
  const btn = $("follow");
  btn.setAttribute("aria-pressed", String(on));
  btn.textContent = on ? "Following the ISS" : "Follow the ISS";
  if (on && state.position) {
    globe.pointOfView({ lat: state.position.latitude * 0.6, lng: state.position.longitude, altitude: 2.2 }, 1200);
  }
}
$("follow").addEventListener("click", () => setFollow(!state.follow));

// ---------------------------------------------------------------------------
// Stream
// ---------------------------------------------------------------------------
let statsTotal = 0;
function applySnapshot(s) {
  state.trail = s.trail || [];
  state.stats = s.stats || [];
  statsTotal = state.stats.length;
  document.querySelector('[data-topic="iss_stats"] .total').textContent = fmt(statsTotal);
  state.events = dedupeEvents(s.events || []);
  state.position = s.position || state.position;
  state.telemetry = s.telemetry || state.telemetry;
  state.distance = s.distance || state.distance;
  state.neighbours = s.neighbours || state.neighbours;
  state.forecast = s.forecast || state.forecast;
  if (s.city_count) $("city-count").textContent = fmt(s.city_count);
  if (s.satellites_enabled && !state.satellitesEnabled) {
    state.satellitesEnabled = true;
    document.querySelectorAll(".sat-only").forEach((el) => (el.hidden = false));
    $("prox-radius").textContent = fmt(s.proximity_radius_km);
    $("forecast-sub").textContent = `Predicted from orbital elements, under ${fmt(s.conjunction_radius_km)} km`;
    loadSatellites();
    setInterval(loadSatellites, 30 * 60 * 1000);
  }
  if (s.repo_url) {
    $("repo-link").href = s.repo_url;
    $("sql-link").href = `${s.repo_url}/tree/main/terraform/sql`;
    $("repo-link").hidden = $("sql-link").hidden = false;
  }
  // The console link only works for members of the deployer's Confluent org.
  if (s.console_url && new URLSearchParams(location.search).has("presenter")) {
    $("console-link").href = s.console_url;
    $("console-link").hidden = false;
  }
  renderPosition();
  renderTelemetry();
  renderDistance();
  renderEvents();
  renderSparks();
  drawPaths();
  if (state.satellitesEnabled) {
    renderNeighbours();
    renderForecast();
  }
  if (state.position && state.follow && !view) {
    globe.pointOfView({ lat: state.position.latitude * 0.6, lng: state.position.longitude, altitude: 2.2 }, 1500);
  }
}

function connect() {
  const es = new EventSource("/api/stream");
  const link = $("link-state");
  const on = (name, fn) => es.addEventListener(name, (ev) => fn(JSON.parse(ev.data)));

  es.onopen = () => { link.dataset.state = "live"; link.textContent = "Live"; };
  es.onerror = () => { link.dataset.state = "lost"; link.textContent = "Reconnecting"; };

  on("snapshot", applySnapshot);
  on("ready", applySnapshot);
  on("iss_position", (p) => {
    state.position = p;
    renderPosition();
    pulse("iss_position");
  });
  on("iss_telemetry", (t) => {
    state.telemetry = t;
    state.trail.push({ t: t.t, latitude: t.latitude, longitude: t.longitude, altitude_km: t.altitude_km, velocity_kmh: t.velocity_kmh, sunlit: t.sunlit });
    if (state.trail.length > 6000) state.trail.shift();
    renderTelemetry();
    pulse("iss_telemetry");
    if (Date.now() - state.lastTrailDraw > 5000) {
      drawPaths();
      renderSparks();
    }
  });
  on("iss_stats", (s) => {
    state.stats.push(s);
    statsTotal += 1;
    document.querySelector('[data-topic="iss_stats"] .total').textContent = fmt(statsTotal);
    if (state.stats.length > 200) state.stats.shift();
    pulse("iss_stats");
  });
  on("iss_events", (e) => {
    addEvent(e);
    pulse("iss_events");
  });
  on("iss_distance", (d) => {
    state.distance = d;
    pulse("iss_distance");
    renderDistance();
  });
  on("iss_proximity", (n) => {
    state.neighbours = n;
    pulse("iss_proximity");
    renderNeighbours();
  });
  on("forecast", (f) => {
    state.forecast = f;
    renderForecast();
  });
  on("metrics", renderMetrics);
}

// ?view=lat,lng[,altitude] opens on a fixed spot instead of following the station.
const view = new URLSearchParams(location.search).get("view");
if (view) {
  const [lat, lng, altitude = 2.2] = view.split(",").map(Number);
  setFollow(false);
  globe.pointOfView({ lat, lng, altitude });
}

connect();
loadTle();
setInterval(loadTle, 30 * 60 * 1000);
setInterval(propagateCatalog, 2000);
setInterval(renderForecast, 30 * 1000);
