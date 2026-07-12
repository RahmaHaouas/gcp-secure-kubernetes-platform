terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "network" {
  source        = "../../modules/network"
  project_id    = var.project_id
  region        = var.region
  name          = "prod"
  subnet_cidr   = "10.0.0.0/20"
  pods_cidr     = "10.4.0.0/14"
  services_cidr = "10.8.0.0/20"
}

module "iam" {
  source     = "../../modules/iam"
  project_id = var.project_id
  name       = "prod"
}

variable "authorized_cidr" {
  type        = string
  description = "Ton IP publique en /32"
}

module "gke" {
  source          = "../../modules/gke"
  project_id      = var.project_id
  name            = "gke-prod"
  location        = var.zone
  network         = module.network.network_name
  subnetwork      = module.network.subnet_name
  node_sa_email   = module.iam.gke_node_sa_email
  authorized_cidr = var.authorized_cidr
  node_count      = 2
}