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
  description = "Ground distance under which a city 'flyover' (closest approach) is reported. Within ~1,000 km the station climbs at least ~20 degrees above the horizon; ~2,200 km is the horizon itself, but with this many cities that floods the flight log."
  type        = number
  default     = 1000
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
    # North and Central America
    { name = "New York", country = "USA", lat = 40.71, lon = -74.01 },
    { name = "Washington", country = "USA", lat = 38.91, lon = -77.04 },
    { name = "Chicago", country = "USA", lat = 41.88, lon = -87.63 },
    { name = "Atlanta", country = "USA", lat = 33.75, lon = -84.39 },
    { name = "Miami", country = "USA", lat = 25.76, lon = -80.19 },
    { name = "Cape Canaveral", country = "USA", lat = 28.39, lon = -80.60 },
    { name = "Houston", country = "USA", lat = 29.76, lon = -95.37 },
    { name = "Starbase", country = "USA", lat = 25.99, lon = -97.15 },
    { name = "Denver", country = "USA", lat = 39.74, lon = -104.99 },
    { name = "Los Angeles", country = "USA", lat = 34.05, lon = -118.24 },
    { name = "San Francisco", country = "USA", lat = 37.77, lon = -122.42 },
    { name = "Seattle", country = "USA", lat = 47.61, lon = -122.33 },
    { name = "Anchorage", country = "USA", lat = 61.22, lon = -149.90 },
    { name = "Toronto", country = "Canada", lat = 43.65, lon = -79.38 },
    { name = "Montreal", country = "Canada", lat = 45.50, lon = -73.57 },
    { name = "Vancouver", country = "Canada", lat = 49.28, lon = -123.12 },
    { name = "Mexico City", country = "Mexico", lat = 19.43, lon = -99.13 },
    { name = "Guadalajara", country = "Mexico", lat = 20.67, lon = -103.35 },
    { name = "Havana", country = "Cuba", lat = 23.11, lon = -82.37 },
    { name = "San Juan", country = "Puerto Rico", lat = 18.47, lon = -66.11 },
    { name = "Guatemala City", country = "Guatemala", lat = 14.63, lon = -90.51 },
    { name = "Panama City", country = "Panama", lat = 8.98, lon = -79.52 },
    # South America
    { name = "Bogota", country = "Colombia", lat = 4.71, lon = -74.07 },
    { name = "Caracas", country = "Venezuela", lat = 10.48, lon = -66.90 },
    { name = "Quito", country = "Ecuador", lat = -0.18, lon = -78.47 },
    { name = "Lima", country = "Peru", lat = -12.05, lon = -77.04 },
    { name = "La Paz", country = "Bolivia", lat = -16.49, lon = -68.12 },
    { name = "Manaus", country = "Brazil", lat = -3.12, lon = -60.02 },
    { name = "Kourou", country = "French Guiana", lat = 5.16, lon = -52.65 },
    { name = "Recife", country = "Brazil", lat = -8.05, lon = -34.88 },
    { name = "Brasilia", country = "Brazil", lat = -15.79, lon = -47.88 },
    { name = "Rio de Janeiro", country = "Brazil", lat = -22.91, lon = -43.17 },
    { name = "Sao Paulo", country = "Brazil", lat = -23.55, lon = -46.63 },
    { name = "Asuncion", country = "Paraguay", lat = -25.26, lon = -57.58 },
    { name = "Santiago", country = "Chile", lat = -33.45, lon = -70.67 },
    { name = "Buenos Aires", country = "Argentina", lat = -34.60, lon = -58.38 },
    { name = "Montevideo", country = "Uruguay", lat = -34.90, lon = -56.16 },
    { name = "Ushuaia", country = "Argentina", lat = -54.80, lon = -68.30 },
    { name = "Easter Island", country = "Chile", lat = -27.15, lon = -109.43 },
    # Europe
    { name = "Reykjavik", country = "Iceland", lat = 64.15, lon = -21.94 },
    { name = "Dublin", country = "Ireland", lat = 53.35, lon = -6.26 },
    { name = "Edinburgh", country = "UK", lat = 55.95, lon = -3.19 },
    { name = "London", country = "UK", lat = 51.51, lon = -0.13 },
    { name = "Paris", country = "France", lat = 48.86, lon = 2.35 },
    { name = "Amsterdam", country = "Netherlands", lat = 52.37, lon = 4.90 },
    { name = "Berlin", country = "Germany", lat = 52.52, lon = 13.40 },
    { name = "Munich", country = "Germany", lat = 48.14, lon = 11.58 },
    { name = "Zurich", country = "Switzerland", lat = 47.37, lon = 8.54 },
    { name = "Madrid", country = "Spain", lat = 40.42, lon = -3.70 },
    { name = "Barcelona", country = "Spain", lat = 41.39, lon = 2.17 },
    { name = "Lisbon", country = "Portugal", lat = 38.72, lon = -9.14 },
    { name = "Ponta Delgada", country = "Azores, Portugal", lat = 37.74, lon = -25.67 },
    { name = "Las Palmas", country = "Canary Islands, Spain", lat = 28.12, lon = -15.43 },
    { name = "Rome", country = "Italy", lat = 41.90, lon = 12.50 },
    { name = "Milan", country = "Italy", lat = 45.46, lon = 9.19 },
    { name = "Vienna", country = "Austria", lat = 48.21, lon = 16.37 },
    { name = "Prague", country = "Czechia", lat = 50.08, lon = 14.44 },
    { name = "Warsaw", country = "Poland", lat = 52.23, lon = 21.01 },
    { name = "Copenhagen", country = "Denmark", lat = 55.68, lon = 12.57 },
    { name = "Oslo", country = "Norway", lat = 59.91, lon = 10.75 },
    { name = "Stockholm", country = "Sweden", lat = 59.33, lon = 18.07 },
    { name = "Helsinki", country = "Finland", lat = 60.17, lon = 24.94 },
    { name = "Kyiv", country = "Ukraine", lat = 50.45, lon = 30.52 },
    { name = "Bucharest", country = "Romania", lat = 44.43, lon = 26.10 },
    { name = "Athens", country = "Greece", lat = 37.98, lon = 23.73 },
    { name = "Istanbul", country = "Turkey", lat = 41.01, lon = 28.98 },
    { name = "Moscow", country = "Russia", lat = 55.76, lon = 37.62 },
    # Middle East and the Caucasus
    { name = "Nicosia", country = "Cyprus", lat = 35.19, lon = 33.38 },
    { name = "Beirut", country = "Lebanon", lat = 33.89, lon = 35.50 },
    { name = "Amman", country = "Jordan", lat = 31.95, lon = 35.93 },
    { name = "Cairo", country = "Egypt", lat = 30.04, lon = 31.24 },
    { name = "Riyadh", country = "Saudi Arabia", lat = 24.71, lon = 46.68 },
    { name = "Jeddah", country = "Saudi Arabia", lat = 21.49, lon = 39.19 },
    { name = "Baghdad", country = "Iraq", lat = 33.31, lon = 44.36 },
    { name = "Tehran", country = "Iran", lat = 35.69, lon = 51.39 },
    { name = "Doha", country = "Qatar", lat = 25.29, lon = 51.53 },
    { name = "Dubai", country = "UAE", lat = 25.20, lon = 55.27 },
    { name = "Muscat", country = "Oman", lat = 23.59, lon = 58.41 },
    { name = "Tbilisi", country = "Georgia", lat = 41.72, lon = 44.79 },
    { name = "Baku", country = "Azerbaijan", lat = 40.41, lon = 49.87 },
    # Africa
    { name = "Casablanca", country = "Morocco", lat = 33.57, lon = -7.59 },
    { name = "Algiers", country = "Algeria", lat = 36.75, lon = 3.06 },
    { name = "Tunis", country = "Tunisia", lat = 36.81, lon = 10.18 },
    { name = "Tripoli", country = "Libya", lat = 32.89, lon = 13.19 },
    { name = "Dakar", country = "Senegal", lat = 14.72, lon = -17.47 },
    { name = "Bamako", country = "Mali", lat = 12.64, lon = -8.00 },
    { name = "Abidjan", country = "Ivory Coast", lat = 5.36, lon = -4.01 },
    { name = "Accra", country = "Ghana", lat = 5.60, lon = -0.19 },
    { name = "Lagos", country = "Nigeria", lat = 6.52, lon = 3.38 },
    { name = "Khartoum", country = "Sudan", lat = 15.50, lon = 32.56 },
    { name = "Addis Ababa", country = "Ethiopia", lat = 9.03, lon = 38.74 },
    { name = "Kampala", country = "Uganda", lat = 0.35, lon = 32.58 },
    { name = "Nairobi", country = "Kenya", lat = -1.29, lon = 36.82 },
    { name = "Kinshasa", country = "DR Congo", lat = -4.44, lon = 15.27 },
    { name = "Dar es Salaam", country = "Tanzania", lat = -6.79, lon = 39.21 },
    { name = "Luanda", country = "Angola", lat = -8.84, lon = 13.23 },
    { name = "Lusaka", country = "Zambia", lat = -15.39, lon = 28.32 },
    { name = "Antananarivo", country = "Madagascar", lat = -18.88, lon = 47.51 },
    { name = "Port Louis", country = "Mauritius", lat = -20.16, lon = 57.50 },
    { name = "Windhoek", country = "Namibia", lat = -22.56, lon = 17.08 },
    { name = "Johannesburg", country = "South Africa", lat = -26.20, lon = 28.05 },
    { name = "Cape Town", country = "South Africa", lat = -33.92, lon = 18.42 },
    # Central, South and East Asia
    { name = "Baikonur", country = "Kazakhstan", lat = 45.92, lon = 63.34 },
    { name = "Yekaterinburg", country = "Russia", lat = 56.84, lon = 60.61 },
    { name = "Novosibirsk", country = "Russia", lat = 55.01, lon = 82.93 },
    { name = "Almaty", country = "Kazakhstan", lat = 43.24, lon = 76.89 },
    { name = "Tashkent", country = "Uzbekistan", lat = 41.30, lon = 69.24 },
    { name = "Kabul", country = "Afghanistan", lat = 34.56, lon = 69.21 },
    { name = "Karachi", country = "Pakistan", lat = 24.86, lon = 67.01 },
    { name = "Lahore", country = "Pakistan", lat = 31.55, lon = 74.34 },
    { name = "Delhi", country = "India", lat = 28.61, lon = 77.21 },
    { name = "Mumbai", country = "India", lat = 19.08, lon = 72.88 },
    { name = "Bangalore", country = "India", lat = 12.97, lon = 77.59 },
    { name = "Sriharikota", country = "India", lat = 13.72, lon = 80.23 },
    { name = "Kolkata", country = "India", lat = 22.57, lon = 88.36 },
    { name = "Colombo", country = "Sri Lanka", lat = 6.93, lon = 79.86 },
    { name = "Kathmandu", country = "Nepal", lat = 27.72, lon = 85.32 },
    { name = "Dhaka", country = "Bangladesh", lat = 23.81, lon = 90.41 },
    { name = "Bangkok", country = "Thailand", lat = 13.76, lon = 100.50 },
    { name = "Hanoi", country = "Vietnam", lat = 21.03, lon = 105.85 },
    { name = "Ho Chi Minh City", country = "Vietnam", lat = 10.82, lon = 106.63 },
    { name = "Kuala Lumpur", country = "Malaysia", lat = 3.14, lon = 101.69 },
    { name = "Singapore", country = "Singapore", lat = 1.35, lon = 103.82 },
    { name = "Jakarta", country = "Indonesia", lat = -6.21, lon = 106.85 },
    { name = "Manila", country = "Philippines", lat = 14.60, lon = 120.98 },
    { name = "Ulaanbaatar", country = "Mongolia", lat = 47.89, lon = 106.91 },
    { name = "Jiuquan", country = "China", lat = 40.96, lon = 100.29 },
    { name = "Chengdu", country = "China", lat = 30.57, lon = 104.07 },
    { name = "Xi'an", country = "China", lat = 34.34, lon = 108.94 },
    { name = "Beijing", country = "China", lat = 39.90, lon = 116.41 },
    { name = "Shanghai", country = "China", lat = 31.23, lon = 121.47 },
    { name = "Hong Kong", country = "China", lat = 22.32, lon = 114.17 },
    { name = "Wenchang", country = "China", lat = 19.61, lon = 110.95 },
    { name = "Taipei", country = "Taiwan", lat = 25.03, lon = 121.57 },
    { name = "Seoul", country = "South Korea", lat = 37.57, lon = 126.98 },
    { name = "Vladivostok", country = "Russia", lat = 43.12, lon = 131.89 },
    { name = "Vostochny", country = "Russia", lat = 51.88, lon = 128.33 },
    { name = "Tokyo", country = "Japan", lat = 35.68, lon = 139.69 },
    { name = "Osaka", country = "Japan", lat = 34.69, lon = 135.50 },
    { name = "Sapporo", country = "Japan", lat = 43.06, lon = 141.35 },
    { name = "Tanegashima", country = "Japan", lat = 30.40, lon = 130.97 },
    # Oceania and the Pacific
    { name = "Guam", country = "USA", lat = 13.44, lon = 144.79 },
    { name = "Port Moresby", country = "Papua New Guinea", lat = -9.44, lon = 147.18 },
    { name = "Darwin", country = "Australia", lat = -12.46, lon = 130.84 },
    { name = "Alice Springs", country = "Australia", lat = -23.70, lon = 133.88 },
    { name = "Perth", country = "Australia", lat = -31.95, lon = 115.86 },
    { name = "Adelaide", country = "Australia", lat = -34.93, lon = 138.60 },
    { name = "Melbourne", country = "Australia", lat = -37.81, lon = 144.96 },
    { name = "Sydney", country = "Australia", lat = -33.87, lon = 151.21 },
    { name = "Brisbane", country = "Australia", lat = -27.47, lon = 153.03 },
    { name = "Noumea", country = "New Caledonia", lat = -22.27, lon = 166.46 },
    { name = "Suva", country = "Fiji", lat = -18.14, lon = 178.44 },
    { name = "Auckland", country = "New Zealand", lat = -36.85, lon = 174.76 },
    { name = "Wellington", country = "New Zealand", lat = -41.29, lon = 174.78 },
    { name = "Mahia", country = "New Zealand", lat = -39.26, lon = 177.86 },
    { name = "Papeete", country = "French Polynesia", lat = -17.54, lon = -149.57 },
    { name = "Honolulu", country = "USA", lat = 21.31, lon = -157.86 },
  ]
}

variable "satellites_enabled" {
  description = "Stream the satellites that share the ISS's altitude and detect close approaches. Adds several thousand messages a second; set to false to run the ISS-only demo."
  type        = bool
  default     = true
}

variable "proximity_radius_km" {
  description = "Satellites within this 3D distance of the ISS are written to iss_proximity every second and highlighted on the globe."
  type        = number
  default     = 500
}

variable "conjunction_radius_km" {
  description = "Closest approaches under this 3D distance become flight-log events and appear in the forecast. Also sets which satellites are streamed: those whose orbits come within this distance (plus 5 km) of the ISS's altitude. 40 km gives about 2 events an hour from ~6,000 satellites; 30 km gives one every few hours from under 1,000."
  type        = number
  default     = 40
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

variable "repo_url" {
  description = "Source repository linked from the dashboard. Set to \"\" to hide the links."
  type        = string
  default     = "https://github.com/MosheBlumbergX/issDemo"
}
