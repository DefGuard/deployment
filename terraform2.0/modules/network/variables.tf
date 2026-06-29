variable "vpc_id" {
  description = "ID of the VPC the Defguard components are deployed into"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC. Used for security group rules that allow VPC-internal access (Core UI/SSH, Edge plain HTTP)."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all created resource names (security groups, RDS parameter/subnet group, network interfaces). Override it to run more than one deployment in the same account/region/VPC without name collisions."
  type        = string
  default     = "defguard"
}

variable "public_subnet_id" {
  description = "Default public subnet (with an internet gateway route) for the Gateway and Edge network interfaces. Used for whichever of the two is not given its own subnet below."
  type        = string
}

variable "gateway_subnet_id" {
  description = "Optional public subnet for the Gateway NIC. Defaults to public_subnet_id when null."
  type        = string
  default     = null
}

variable "edge_subnet_id" {
  description = "Optional public subnet for the Edge NIC. Defaults to public_subnet_id when null."
  type        = string
  default     = null
}

variable "core_subnet_id" {
  description = "Private subnet for the Core network interface. Must have outbound internet (NAT) for the deb download and license checks."
  type        = string
}

variable "db_subnet_ids" {
  description = "Subnets for the RDS subnet group. Must span at least two availability zones."
  type        = list(string)
}

variable "ssh_admin_cidr" {
  description = "CIDR allowed to SSH into the components. null (default) disables SSH entirely (no port-22 ingress is created). Set a /32 to allow SSH from a single host; avoid 0.0.0.0/0."
  type        = string
  default     = null
}

variable "core_http_port" {
  description = "Core web UI port (reachable only from within the VPC)"
  type        = number
  default     = 8000
}

variable "gateway_grpc_port" {
  description = "Gateway gRPC port that Core dials for adoption/control"
  type        = number
  default     = 50066
}

variable "wireguard_port" {
  description = "UDP port the WireGuard VPN listens on (public)"
  type        = number
  default     = 51820
}

variable "edge_grpc_port" {
  description = "Edge gRPC port that Core dials for adoption/control"
  type        = number
  default     = 50051
}

variable "edge_http_port" {
  description = "Edge plain HTTP API port (reachable only from within the VPC)"
  type        = number
  default     = 8080
}

variable "edge_https_port" {
  description = "Edge public HTTPS port"
  type        = number
  default     = 443
}

variable "db_name" {
  description = "Name of the database created for Defguard Core"
  type        = string
  default     = "defguard"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "defguard"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_engine_version" {
  description = "Major PostgreSQL engine version. The parameter group family is derived from this."
  type        = string
  default     = "18"
}

variable "db_storage" {
  description = "Allocated storage for the database in GB"
  type        = number
  default     = 20
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}
