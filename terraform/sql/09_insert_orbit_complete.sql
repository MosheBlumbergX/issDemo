-- Complex event processing: an orbit is an ascending node, followed by
-- everything until the next ascending node. Flink measures the orbital period.
INSERT INTO `iss_events`
SELECT
  `end_time` AS `event_time`,
  'ORBIT_COMPLETE' AS `event_type`,
  'Orbit complete' AS `title`,
  CONCAT(
    'Period ', CAST(ROUND(`period_min`, 2) AS STRING), ' min, ',
    CAST(CAST(ROUND(`distance_km`, 0) AS INT) AS STRING), ' km ground track, ',
    CAST(`samples` AS STRING), ' fixes'
  ) AS `detail`,
  `end_lat`  AS `latitude`,
  `end_lon`  AS `longitude`,
  `distance_km`,
  `period_min` AS `duration_min`
FROM (
  SELECT *, CAST(TIMESTAMPDIFF(SECOND, `start_time`, `end_time`) AS DOUBLE) / 60.0 AS `period_min`
  FROM `iss_telemetry`
  MATCH_RECOGNIZE (
    ORDER BY `event_time`
    MEASURES
      A.`event_time`                  AS `start_time`,
      C.`event_time`                  AS `end_time`,
      C.`latitude`                    AS `end_lat`,
      C.`longitude`                   AS `end_lon`,
      SUM(B.`step_km`)                AS `distance_km`,
      COUNT(B.`latitude`) + 2         AS `samples`
    ONE ROW PER MATCH
    AFTER MATCH SKIP TO LAST C
    PATTERN (A B+ C)
    DEFINE
      A AS A.`prev_latitude` < 0 AND A.`latitude` >= 0,
      B AS NOT (B.`prev_latitude` < 0 AND B.`latitude` >= 0),
      C AS C.`prev_latitude` < 0 AND C.`latitude` >= 0
  )
)
-- Ignore matches that span a producer outage.
WHERE `period_min` BETWEEN 85 AND 100;
