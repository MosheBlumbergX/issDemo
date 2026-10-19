CREATE TABLE IF NOT EXISTS `iss_proximity` (
  `event_time`       TIMESTAMP_LTZ(3) NOT NULL,
  `norad_id`         INT              NOT NULL,
  `name`             STRING,
  `latitude`         DOUBLE,
  `longitude`        DOUBLE,
  `altitude_km`      DOUBLE,
  `iss_altitude_km`  DOUBLE,
  `distance_km`      DOUBLE,
  WATERMARK FOR `event_time` AS `event_time` - INTERVAL '2' SECOND
)
DISTRIBUTED INTO 1 BUCKETS
WITH (
  'changelog.mode'       = 'append',
  'value.format'         = 'avro-registry',
  'kafka.retention.time' = '1 d'
);
