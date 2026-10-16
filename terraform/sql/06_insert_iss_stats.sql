-- Sliding 1-minute window, refreshed every 10 seconds.
INSERT INTO `iss_stats`
SELECT
  `window_start`,
  `window_end`,
  COUNT(*)                            AS `samples`,
  AVG(`velocity_kmh`)                 AS `avg_velocity_kmh`,
  MAX(`velocity_kmh`)                 AS `max_velocity_kmh`,
  AVG(`ground_speed_kmh`)             AS `avg_ground_speed_kmh`,
  AVG(`altitude_km`)                  AS `avg_altitude_km`,
  MIN(`altitude_km`)                  AS `min_altitude_km`,
  MAX(`altitude_km`)                  AS `max_altitude_km`,
  SUM(`step_km`)                      AS `distance_km`,
  MAX(`latitude`) - MIN(`latitude`)   AS `lat_change_deg`
FROM TABLE(
  HOP(TABLE `iss_telemetry`, DESCRIPTOR(`event_time`), INTERVAL '10' SECOND, INTERVAL '1' MINUTE)
)
GROUP BY `window_start`, `window_end`;
