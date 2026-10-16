CREATE TABLE IF NOT EXISTS `iss_stats` (
  `window_start`          TIMESTAMP(3),
  `window_end`            TIMESTAMP(3),
  `samples`               BIGINT,
  `avg_velocity_kmh`      DOUBLE,
  `max_velocity_kmh`      DOUBLE,
  `avg_ground_speed_kmh`  DOUBLE,
  `avg_altitude_km`       DOUBLE,
  `min_altitude_km`       DOUBLE,
  `max_altitude_km`       DOUBLE,
  `distance_km`           DOUBLE,
  `lat_change_deg`        DOUBLE
)
DISTRIBUTED INTO 1 BUCKETS
WITH (
  'changelog.mode' = 'append',
  'value.format'   = 'avro-registry'
);
