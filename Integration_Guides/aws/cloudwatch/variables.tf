variable "accuknox_suffix" {
  type    = string
  default = "accuknox_cloudtrail_collector"
}

variable "username" {
  type      = string
  sensitive = true
}

variable "password" {
  type      = string
  sensitive = true
}

variable "chunk_size" {
  type = string
  # defults to 3MB in lambda code
  default = "3145728"
}

variable "line_limit" {
  type = string
  # defults to 1000 lines in lambda code
  default = "1000"
}

variable "insecure_tls" {
  type = string
  # defults to false in lambda code
  # can either be false or true // as strings
  default = "false"
}

variable "cloudwatch_target_url" {
  type = string
}

variable "log_groups" {
  type    = list(string)
  default = []
}