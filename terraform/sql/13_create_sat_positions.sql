CREATE TABLE IF NOT EXISTS `sat_positions` (
  `norad_id`     INT              NOT NULL,
  `name`         STRING,
  `latitude`     DOUBLE           NOT NULL,
  `longitude`    DOUBLE           NOT NULL,
  `altitude_km`  DOUBLE           NOT NULL,
  `event_time`   TIMESTAMP_LTZ(3) NOT NULL,
  WATERMARK FOR `event_time` AS `event_time` - INTERVAL '2' SECOND
)
DISTRIBUTED INTO 1 BUCKETS
WITH (
  'changelog.mode'       = 'append',
  'value.format'         = 'avro-registry',
  'kafka.retention.time' = '1 h'
);
