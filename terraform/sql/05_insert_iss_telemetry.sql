-- Enrich raw positions: unit conversions, Flink-computed ground-track speed
-- and heading (haversine/bearing between consecutive fixes via LAG), day/night,
-- hemisphere and north/south-bound direction.
INSERT INTO `iss_telemetry`
SELECT
  `event_time`,
  `latitude`,
  `longitude`,
  `altitude_km`,
  `velocity_kmh`,
  `velocity_kmh` * 0.621371                                     AS `velocity_mph`,
  `velocity_kmh` / 3600.0                                       AS `velocity_kms`,
  CASE WHEN `dt_s` > 0 AND `dt_s` <= 30
       THEN `step_km` / `dt_s` * 3600.0 END                     AS `ground_speed_kmh`,
  CASE WHEN `bearing` < 0 THEN `bearing` + 360 ELSE `bearing` END AS `heading_deg`,
  CASE WHEN `dt_s` > 0 AND `dt_s` <= 30 THEN `step_km` END      AS `step_km`,
  `sunlit`,
  CASE WHEN `latitude` >= 0 THEN 'NORTH' ELSE 'SOUTH' END       AS `hemisphere`,
  CASE WHEN `prev_latitude` IS NULL THEN CAST(NULL AS STRING)
       WHEN `latitude` >= `prev_latitude` THEN 'NORTHBOUND'
       ELSE 'SOUTHBOUND' END                                    AS `direction`,
  `prev_latitude`,
  `prev_longitude`,
  `prev2_latitude`,
  `prev2_longitude`,
  `prev_sunlit`
FROM (
  SELECT
    *,
    2 * 6371.0 * ASIN(SQRT(
        POWER(SIN(RADIANS(`latitude` - `prev_latitude`) / 2), 2)
      + COS(RADIANS(`prev_latitude`)) * COS(RADIANS(`latitude`))
        * POWER(SIN(RADIANS(`longitude` - `prev_longitude`) / 2), 2)
    )) AS `step_km`,
    DEGREES(ATAN2(
        SIN(RADIANS(`longitude` - `prev_longitude`)) * COS(RADIANS(`latitude`)),
        COS(RADIANS(`prev_latitude`)) * SIN(RADIANS(`latitude`))
      - SIN(RADIANS(`prev_latitude`)) * COS(RADIANS(`latitude`)) * COS(RADIANS(`longitude` - `prev_longitude`))
    )) AS `bearing`,
    CAST(TIMESTAMPDIFF(SECOND, `prev_time`, `event_time`) AS DOUBLE) AS `dt_s`
  FROM (
    SELECT
      `event_time`,
      `latitude`,
      `longitude`,
      `altitude_km`,
      `velocity_kmh`,
      `visibility` <> 'eclipsed'                                           AS `sunlit`,
      LAG(`latitude`)                   OVER (ORDER BY `event_time`)       AS `prev_latitude`,
      LAG(`longitude`)                  OVER (ORDER BY `event_time`)       AS `prev_longitude`,
      LAG(`latitude`, 2)                OVER (ORDER BY `event_time`)       AS `prev2_latitude`,
      LAG(`longitude`, 2)               OVER (ORDER BY `event_time`)       AS `prev2_longitude`,
      LAG(`event_time`)                 OVER (ORDER BY `event_time`)       AS `prev_time`,
      LAG(`visibility` <> 'eclipsed')   OVER (ORDER BY `event_time`)       AS `prev_sunlit`
    FROM `iss_position`
  )
);
