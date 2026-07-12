variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "location" {
  type        = string
  description = "Zone (ex: europe-west1-b). Zonal = moins cher que regional."
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "node_sa_email" {
  type        = string
  description = "Email du service account dédié aux nœuds"
}

variable "authorized_cidr" {
  type        = string
  description = "Ton IP publique en /32 — seule autorisée à joindre le control plane"
}

variable "master_cidr" {
  type        = string
  description = "Plage /28 privée pour le control plane"
  default     = "172.16.0.0/28"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}