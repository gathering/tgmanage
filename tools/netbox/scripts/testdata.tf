##
## EX2200 and EX3300 device types must be added
##
##
terraform {
  required_providers {
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 3.2.1"
    }
  }
}

# example provider configuration for https://demo.netbox.dev
provider "netbox" {
  server_url = "http://localhost:8000"
  api_token  = "14ef292da3c0564c591cd39eb22fa2cbab75b141"
}

resource "netbox_manufacturer" "juniper" {
  name = "Juniper"
}

resource "netbox_site" "site" {
  name = "Vikingskipet"
}

resource "netbox_location" "loc" {
  name    = "Ringen"
  site_id = netbox_site.site.id
}

resource "netbox_device_role" "access" {
  color_hex = "ff5722"
  name      = "Access switch"
  slug      = "access-switch"
}
resource "netbox_device_role" "leaf" {
  color_hex = "ff5722"
  name      = "Leaf"
  slug      = "leaf"
}
resource "netbox_device_role" "distro" {
  color_hex = "ff5722"
  name      = "Distro"
  slug      = "distro"
}
resource "netbox_device_role" "utskutt_distro" {
  color_hex = "ff5722"
  name      = "Utskutt Distro"
  slug      = "utskutt-distro"
}

resource "netbox_ipam_role" "clients" {
  name = "Clients"
}

resource "netbox_vrf" "clients" {
  name = "CLIENTS"
}

resource "netbox_vlan_group" "fabric" {
  max_vid = 10
  min_vid = 400
  name    = "client-vlans"
  slug    = "client-vlans"
}

resource "netbox_vlan" "mgmt" {
  name = "juniper-mgmt"
  vid  = 10
}

resource "netbox_prefix" "fabric_v4" {
  prefix      = "10.25.0.0/16"
  status      = "container"
  description = "Fabric v4 clients"
}

resource "netbox_prefix" "fabric_v6" {
  prefix      = "2a06:5844:e::/48"
  status      = "container"
  description = "Fabric v6 clients"
}

resource "netbox_prefix" "mgmt_v4" {
  prefix  = "185.110.149.0/25"
  status  = "active"
  vlan_id = netbox_vlan.mgmt.id
}

resource "netbox_prefix" "mgmt_v6" {
  prefix  = "2a06:5841:f::/64"
  status  = "active"
  vlan_id = netbox_vlan.mgmt.id
}
