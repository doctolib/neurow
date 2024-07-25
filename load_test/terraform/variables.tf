variable "region" {
  type = string
}

variable "resource_prefix" {
  type    = string
  default = "neurow"
}

variable "dd_secret_arn" {
  type = string
}

variable "dd_tags" {
  type    = string
  default = ""
}

variable "instance_type" {
  type    = string
  default = "c6i.large"
}

variable "desired_capacity" {
  type    = number
  default = 10
}

variable "min_size" {
  type    = number
  default = 0
}

variable "max_size" {
  type    = number
  default = 100
}

variable "nb_users" {
  type    = number
  default = 5000
}

variable "neurow_revision" {
  type    = string
  default = ""
}

variable "neurow_config" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "extended_policy" {
  type    = string
  default = ""
}