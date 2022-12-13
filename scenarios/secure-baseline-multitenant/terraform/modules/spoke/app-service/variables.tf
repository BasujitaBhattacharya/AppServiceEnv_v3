variable "application_name" {
  type        = string
  description = "The name of your application"
  default     = "app-svc-lz-4254"
}

variable "resource_group" {
  type        = string
  description = "The name of the resource group where all resources in this example should be created."
}

variable "environment" {
  type        = string
  description = "The environment (dev, test, prod...)"
  default     = "dev"
}

variable "location" {
  type        = string
  description = "The Azure region where all resources in this example should be created"
  default     = "westeurope"
}

variable "sku_name" {
  type        = string
  description = "The sku name for the app service plan"
  default     = "S1"
  validation {
    condition = contains(["S1", "S2", "S3", "P1v2", "P2v2", "P3v2"], var.sku_name)
    error_message = "Please, choose among one of the following SKUs for production workloads: S1, S2, S3, P1v2, P2v2 or P3v2"
  }
}

variable "os_type" {
  type        = string
  description = "The operating system for the app service plan"
  default     = "Windows"
  validation {
    condition = contains(["Windows", "Linux"], var.os_type)
    error_message = "Please, choose among one of the following operating systems: Windows or Linux"
  }
}

variable "app_svc_integration_subnet_id" {
  type        = string
  description = "The subnet id where the app service will be integrated"
}

variable "front_door_integration_subnet_id" {
  type        = string
  description = "The subnet id where the front door will be integrated"
}

variable "private_dns_zone_id" {
  type        = string
  description = "The private dns zone id where the app service will be integrated"
}