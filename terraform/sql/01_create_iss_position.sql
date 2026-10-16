CREATE TABLE IF NOT EXISTS `iss_position` (
  `satellite_id`  INT              NOT NULL,
  `latitude`      DOUBLE           NOT NULL,
  `longitude`     DOUBLE           NOT NULL,
  `altitude_km`   DOUBLE           NOT NULL,
  `velocity_kmh`  DOUBLE           NOT NULL,
  `visibility`    STRING           NOT NULL,
  `footprint_km`  DOUBLE,
  `solar_lat`     DOUBLE,
  `solar_lon`     DOUBLE,
  `source`        STRING,
  `event_time`    TIMESTAMP_LTZ(3) NOT NULL,
  WATERMARK FOR `event_time` AS `event_time` - INTERVAL '2' SECOND
)
DISTRIBUTED INTO 1 BUCKETS
WITH (
  'changelog.mode' = 'append',
  'value.format'   = 'avro-registry'
);
