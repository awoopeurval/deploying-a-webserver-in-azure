variable "prefix" {
  description = "The prefix which should be used for all resources in this project"
  default = "udacity-proj"
}

variable "location" {
  description = "The Azure Region in which all resources in this project should be created."
  default = "East US"
}

variable "resource_group_name" {
  type = string
  description = "Name of the existing Resource Group"
  default="Azuredevops"
}

variable "username" {
    description = "The username of VMs"
    default = "mitchadmin"
}

variable "password" {
    description = "The password for VMs"
    default="Yeshua@12"
}

variable "address_space" {
    description = "Insert the address_space of this VNet"
    default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type = string
  description = "CIDR block for the subnet"
  default = "10.0.2.0/24"
}

variable "vm_count" {
    type = number
    description = "Number of VMs in this VMAS"
    default = 2
}

variable "tags" {
  description = "Tags to apply to resources"
  type = map(string)
  default = {
    usage = "udacity"
    env = "testing"
  }
}