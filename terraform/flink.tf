locals {
  flink_properties = {
    "sql.current-catalog"  = confluent_environment.iss.display_name
    "sql.current-database" = confluent_kafka_cluster.iss.display_name
  }

  city_rows = join(",\n    ", [
    for c in var.cities :
    "ROW(CAST('${replace(c.name, "'", "''")}' AS STRING), CAST('${replace(c.country, "'", "''")}' AS STRING), CAST(${c.lat} AS DOUBLE), CAST(${c.lon} AS DOUBLE))"
  ])

  # DDL first (tables/topics/schemas), then the long-running pipelines.
  ddl = {
    "iss-ddl-position"  = file("${path.module}/sql/01_create_iss_position.sql")
    "iss-ddl-telemetry" = file("${path.module}/sql/02_create_iss_telemetry.sql")
    "iss-ddl-stats"     = file("${path.module}/sql/03_create_iss_stats.sql")
    "iss-ddl-events"    = file("${path.module}/sql/04_create_iss_events.sql")
    "iss-ddl-distance"  = file("${path.module}/sql/11_create_iss_distance.sql")
  }

  # Statements that read only from iss_position.
  dml_stage1 = {
    "iss-enrich-telemetry"  = file("${path.module}/sql/05_insert_iss_telemetry.sql")
    "iss-distance-odometer" = file("${path.module}/sql/12_insert_iss_distance.sql")
  }

  # Statements that read from iss_telemetry.
  dml_stage2 = {
    "iss-stats-hop-window" = file("${path.module}/sql/06_insert_iss_stats.sql")
    "iss-orbital-events"   = file("${path.module}/sql/07_insert_orbital_events.sql")
    "iss-city-flyovers" = templatefile("${path.module}/sql/08_insert_city_flyovers.sql.tftpl", {
      cities    = local.city_rows
      radius_km = var.flyover_radius_km
    })
    "iss-orbit-complete-cep" = file("${path.module}/sql/09_insert_orbit_complete.sql")
    "iss-eclipse-pass-cep"   = file("${path.module}/sql/10_insert_eclipse_pass.sql")
  }
}

resource "confluent_flink_statement" "ddl" {
  for_each = local.ddl

  statement_name = each.key
  statement      = each.value
  properties     = local.flink_properties

  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.iss.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.iss.id
  }
  principal {
    id = confluent_service_account.iss_app.id
  }
  rest_endpoint = data.confluent_flink_region.iss.rest_endpoint
  credentials {
    key    = confluent_api_key.flink.id
    secret = confluent_api_key.flink.secret
  }

  depends_on = [confluent_api_key.kafka, confluent_api_key.schema_registry]
}

resource "confluent_flink_statement" "dml_stage1" {
  for_each = local.dml_stage1

  statement_name = each.key
  statement      = each.value
  properties     = local.flink_properties

  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.iss.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.iss.id
  }
  principal {
    id = confluent_service_account.iss_app.id
  }
  rest_endpoint = data.confluent_flink_region.iss.rest_endpoint
  credentials {
    key    = confluent_api_key.flink.id
    secret = confluent_api_key.flink.secret
  }

  depends_on = [confluent_flink_statement.ddl]
}

resource "confluent_flink_statement" "dml_stage2" {
  for_each = local.dml_stage2

  statement_name = each.key
  statement      = each.value
  properties     = local.flink_properties

  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.iss.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.iss.id
  }
  principal {
    id = confluent_service_account.iss_app.id
  }
  rest_endpoint = data.confluent_flink_region.iss.rest_endpoint
  credentials {
    key    = confluent_api_key.flink.id
    secret = confluent_api_key.flink.secret
  }

  depends_on = [confluent_flink_statement.ddl]
}
