-- Odometer: ground distance per step (LAG + haversine), then a rolling one-hour
-- sum and a running total. Reads the raw topic so it updates every second.
-- Each OVER frame needs its own query level.
INSERT INTO `iss_distance`
SELECT
  `event_time`,
  `distance_1h_km`,
  SUM(`step_km`)    OVER (ORDER BY `event_time` RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS `distance_total_km`,
  MIN(`event_time`) OVER (ORDER BY `event_time` RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS `tracked_since`
FROM (
  SELECT
    `event_time`,
    `step_km`,
    SUM(`step_km`) OVER (ORDER BY `event_time` RANGE BETWEEN INTERVAL '1' HOUR PRECEDING AND CURRENT ROW) AS `distance_1h_km`
  FROM (
    SELECT
      `event_time`,
      CASE WHEN TIMESTAMPDIFF(SECOND, `prev_time`, `event_time`) BETWEEN 1 AND 30 THEN
        2 * 6371.0 * ASIN(SQRT(
            POWER(SIN(RADIANS(`latitude` - `prev_latitude`) / 2), 2)
          + COS(RADIANS(`prev_latitude`)) * COS(RADIANS(`latitude`))
            * POWER(SIN(RADIANS(`longitude` - `prev_longitude`) / 2), 2)
        ))
      ELSE 0.0 END AS `step_km`
    FROM (
      SELECT
        `event_time`, `latitude`, `longitude`,
        LAG(`latitude`)   OVER (ORDER BY `event_time`) AS `prev_latitude`,
        LAG(`longitude`)  OVER (ORDER BY `event_time`) AS `prev_longitude`,
        LAG(`event_time`) OVER (ORDER BY `event_time`) AS `prev_time`
      FROM `iss_position`
    )
  )
);
