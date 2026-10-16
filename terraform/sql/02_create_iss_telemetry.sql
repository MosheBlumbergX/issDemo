CREATE TABLE IF NOT EXISTS `iss_telemetry` (
  `event_time`        TIMESTAMP_LTZ(3) NOT NULL,
  `latitude`          DOUBLE,
  `longitude`         DOUBLE,
  `altitude_km`       DOUBLE,
  `velocity_kmh`      DOUBLE,
  `velocity_mph`      DOUBLE,
  `velocity_kms`      DOUBLE,
  `ground_speed_kmh`  DOUBLE,
  `heading_deg`       DOUBLE,
  `step_km`           DOUBLE,
  `sunlit`            BOOLEAN,
  `hemisphere`        STRING,
  `direction`         STRING,
  `prev_latitude`     DOUBLE,
  `prev_longitude`    DOUBLE,
  `prev2_latitude`    DOUBLE,
  `prev2_longitude`   DOUBLE,
  `prev_sunlit`       BOOLEAN,
  WATERMARK FOR `event_time` AS `event_time` - INTERVAL '2' SECOND
)
DISTRIBUTED INTO 1 BUCKETS
WITH (
  'changelog.mode' = 'append',
  'value.format'   = 'avro-registry'
);
