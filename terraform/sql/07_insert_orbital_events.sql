-- Detect state transitions between consecutive fixes:
-- equator crossings (orbital nodes), orbital sunrise/sunset and latitude extremes.
INSERT INTO `iss_events`
SELECT
  `event_time`,
  `event_type`,
  CASE `event_type`
    WHEN 'ASCENDING_NODE'     THEN 'Equator crossed, heading north'
    WHEN 'DESCENDING_NODE'    THEN 'Equator crossed, heading south'
    WHEN 'ORBITAL_SUNRISE'    THEN 'Orbital sunrise'
    WHEN 'ORBITAL_SUNSET'     THEN 'Orbital sunset'
    WHEN 'NORTHERNMOST_POINT' THEN 'Northernmost point of orbit'
    WHEN 'SOUTHERNMOST_POINT' THEN 'Southernmost point of orbit'
  END AS `title`,
  CONCAT(
    'lat ', CAST(ROUND(`latitude`, 2) AS STRING),
    ', lon ', CAST(ROUND(`longitude`, 2) AS STRING),
    ', alt ', CAST(ROUND(`altitude_km`, 1) AS STRING), ' km'
  ) AS `detail`,
  `latitude`,
  `longitude`,
  CAST(NULL AS DOUBLE) AS `distance_km`,
  CAST(NULL AS DOUBLE) AS `duration_min`
FROM (
  SELECT
    `event_time`, `latitude`, `longitude`, `altitude_km`,
    CASE
      WHEN `prev_latitude` < 0 AND `latitude` >= 0          THEN 'ASCENDING_NODE'
      WHEN `prev_latitude` >= 0 AND `latitude` < 0          THEN 'DESCENDING_NODE'
      WHEN `prev_sunlit` = FALSE AND `sunlit` = TRUE        THEN 'ORBITAL_SUNRISE'
      WHEN `prev_sunlit` = TRUE AND `sunlit` = FALSE        THEN 'ORBITAL_SUNSET'
      WHEN `prev_direction` = 'NORTHBOUND' AND `direction` = 'SOUTHBOUND' THEN 'NORTHERNMOST_POINT'
      WHEN `prev_direction` = 'SOUTHBOUND' AND `direction` = 'NORTHBOUND' THEN 'SOUTHERNMOST_POINT'
    END AS `event_type`
  FROM (
    SELECT *, LAG(`direction`) OVER (ORDER BY `event_time`) AS `prev_direction`
    FROM `iss_telemetry`
  )
)
WHERE `event_type` IS NOT NULL;
