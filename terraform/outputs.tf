output "environment_id" {
  value = confluent_environment.iss.id
}

output "kafka_cluster_id" {
  value = confluent_kafka_cluster.iss.id
}

output "flink_compute_pool_id" {
  value = confluent_flink_compute_pool.iss.id
}

output "bootstrap_servers" {
  value = replace(confluent_kafka_cluster.iss.bootstrap_endpoint, "SASL_SSL://", "")
}

output "kafka_api_key" {
  value = confluent_api_key.kafka.id
}

output "kafka_api_secret" {
  value     = confluent_api_key.kafka.secret
  sensitive = true
}

output "schema_registry_url" {
  value = data.confluent_schema_registry_cluster.sr.rest_endpoint
}

output "schema_registry_api_key" {
  value = confluent_api_key.schema_registry.id
}

output "schema_registry_api_secret" {
  value     = confluent_api_key.schema_registry.secret
  sensitive = true
}

output "flink_statements" {
  value = concat(
    keys(local.ddl),
    keys(local.dml_stage1),
    keys(local.dml_stage2),
  )
}

output "console_url" {
  value = "https://confluent.cloud/environments/${confluent_environment.iss.id}/flink/statements"
}

output "dashboard_url" {
  value = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "app_instance_id" {
  description = "Shell access: aws ssm start-session --target <id>"
  value       = aws_instance.app.id
}
