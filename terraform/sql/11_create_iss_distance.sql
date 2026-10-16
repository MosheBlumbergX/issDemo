CREATE TABLE IF NOT EXISTS `iss_distance` (
  `event_time`         TIMESTAMP_LTZ(3) NOT NULL,
  `distance_1h_km`     DOUBLE,
  `distance_total_km`  DOUBLE,
  `tracked_since`      TIMESTAMP_LTZ(3)
)
DISTRIBUTED INTO 1 BUCKETS
WITH (
  'changelog.mode' = 'append',
  'value.format'   = 'avro-registry'
);
