variable "accuknox_suffix" {
  type    = string
  default = "accuknox-cloudtrail-collector"
}

variable "username" {
  type      = string
  sensitive = true
}

variable "password" {
  type      = string
  sensitive = true
}
variable "bucket_arn" {
  type = string
}
variable "bucket_name" {
  type = string
}


variable "target_url" {
  type = string
}

variable "chunk_size" {
  type = string
  # defults to 3MB in lambda code
  default = ""
}

variable "line_limit" {
  type = string
  # defults to 1000 lines in lambda code
  default = ""
}

variable "insecure_tls" {
  type = string
  # defults to false in lambda code
  # can either be false or true // as strings
  default = ""
}