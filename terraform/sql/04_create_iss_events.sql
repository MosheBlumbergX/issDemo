CREATE TABLE IF NOT EXISTS `iss_events` (
  `event_time`   TIMESTAMP_LTZ(3) NOT NULL,
  `event_type`   STRING NOT NULL,
  `title`        STRING,
  `detail`       STRING,
  `latitude`     DOUBLE,
  `longitude`    DOUBLE,
  `distance_km`  DOUBLE,
  `duration_min` DOUBLE
)
DISTRIBUTED INTO 1 BUCKETS
WITH (
  'changelog.mode' = 'append',
  'value.format'   = 'avro-registry'
);
