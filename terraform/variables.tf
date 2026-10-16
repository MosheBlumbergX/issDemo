variable "environment_name" {
  description = "Confluent Cloud environment display name (also used as a prefix)."
  type        = string
  default     = "iss-demo"
}

variable "cluster_name" {
  description = "Kafka cluster display name (also the Flink database name)."
  type        = string
  default     = "iss-cluster"
}

variable "cloud" {
  type    = string
  default = "AWS"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "flink_max_cfu" {
  description = "Upper bound for the Flink compute pool. You pay only for CFUs actually used."
  type        = number
  default     = 20
}

variable "flyover_radius_km" {
  description = "Ground distance under which a city 'flyover' (closest approach) is reported. ~2,000 km is roughly the horizon from the ISS."
  type        = number
  default     = 2000
}

variable "cities" {
  description = "Reference points for flyover detection (inlined into the Flink SQL)."
  type = list(object({
    name    = string
    country = string
    lat     = number
    lon     = number
  }))
  default = [
    { name = "Tel Aviv", country = "Israel", lat = 32.08, lon = 34.78 },
    { name = "New York", country = "USA", lat = 40.71, lon = -74.01 },
    { name = "San Francisco", country = "USA", lat = 37.77, lon = -122.42 },
    { name = "Houston", country = "USA", lat = 29.76, lon = -95.37 },
    { name = "Cape Canaveral", country = "USA", lat = 28.39, lon = -80.60 },
    { name = "Toronto", country = "Canada", lat = 43.65, lon = -79.38 },
    { name = "Mexico City", country = "Mexico", lat = 19.43, lon = -99.13 },
    { name = "Sao Paulo", country = "Brazil", lat = -23.55, lon = -46.63 },
    { name = "Buenos Aires", country = "Argentina", lat = -34.60, lon = -58.38 },
    { name = "Lima", country = "Peru", lat = -12.05, lon = -77.04 },
    { name = "London", country = "UK", lat = 51.51, lon = -0.13 },
    { name = "Paris", country = "France", lat = 48.86, lon = 2.35 },
    { name = "Berlin", country = "Germany", lat = 52.52, lon = 13.40 },
    { name = "Madrid", country = "Spain", lat = 40.42, lon = -3.70 },
    { name = "Rome", country = "Italy", lat = 41.90, lon = 12.50 },
    { name = "Istanbul", country = "Turkey", lat = 41.01, lon = 28.98 },
    { name = "Cairo", country = "Egypt", lat = 30.04, lon = 31.24 },
    { name = "Lagos", country = "Nigeria", lat = 6.52, lon = 3.38 },
    { name = "Nairobi", country = "Kenya", lat = -1.29, lon = 36.82 },
    { name = "Cape Town", country = "South Africa", lat = -33.92, lon = 18.42 },
    { name = "Dubai", country = "UAE", lat = 25.20, lon = 55.27 },
    { name = "Mumbai", country = "India", lat = 19.08, lon = 72.88 },
    { name = "Bangalore", country = "India", lat = 12.97, lon = 77.59 },
    { name = "Baikonur", country = "Kazakhstan", lat = 45.92, lon = 63.34 },
    { name = "Moscow", country = "Russia", lat = 55.76, lon = 37.62 },
    { name = "Beijing", country = "China", lat = 39.90, lon = 116.41 },
    { name = "Shanghai", country = "China", lat = 31.23, lon = 121.47 },
    { name = "Tokyo", country = "Japan", lat = 35.68, lon = 139.69 },
    { name = "Seoul", country = "South Korea", lat = 37.57, lon = 126.98 },
    { name = "Singapore", country = "Singapore", lat = 1.35, lon = 103.82 },
    { name = "Jakarta", country = "Indonesia", lat = -6.21, lon = 106.85 },
    { name = "Sydney", country = "Australia", lat = -33.87, lon = 151.21 },
    { name = "Perth", country = "Australia", lat = -31.95, lon = 115.86 },
    { name = "Auckland", country = "New Zealand", lat = -36.85, lon = 174.76 },
    { name = "Honolulu", country = "USA", lat = 21.31, lon = -157.86 },
  ]
}

variable "aws_profile" {
  description = "AWS CLI profile used to deploy the dashboard (set in terraform.tfvars)."
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region for the dashboard host; keep it next to the Kafka cluster."
  type        = string
  default     = "us-east-1"
}

variable "aws_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "aws_tags" {
  description = "Extra tags for every AWS resource, e.g. ones your organisation's tagging policy requires."
  type        = map(string)
  default     = {}
}
