-- Complex event processing: sunset -> (in Earth's shadow)+ -> sunrise.
-- Flink measures how long the station spent in darkness.
INSERT INTO `iss_events`
SELECT
  `end_time` AS `event_time`,
  'ECLIPSE_PASS' AS `event_type`,
  'Night pass complete' AS `title`,
  CONCAT('Spent ', CAST(ROUND(`duration_min`, 1) AS STRING), ' min in Earth''s shadow') AS `detail`,
  `end_lat` AS `latitude`,
  `end_lon` AS `longitude`,
  CAST(NULL AS DOUBLE) AS `distance_km`,
  `duration_min`
FROM (
  SELECT *, CAST(TIMESTAMPDIFF(SECOND, `start_time`, `end_time`) AS DOUBLE) / 60.0 AS `duration_min`
  FROM `iss_telemetry`
  MATCH_RECOGNIZE (
    ORDER BY `event_time`
    MEASURES
      S.`event_time` AS `start_time`,
      R.`event_time` AS `end_time`,
      R.`latitude`   AS `end_lat`,
      R.`longitude`  AS `end_lon`
    ONE ROW PER MATCH
    AFTER MATCH SKIP PAST LAST ROW
    PATTERN (S N* R)
    DEFINE
      S AS S.`sunlit` = FALSE AND S.`prev_sunlit` = TRUE,
      N AS N.`sunlit` = FALSE,
      R AS R.`sunlit` = TRUE
  )
)
WHERE `duration_min` BETWEEN 5 AND 50;
