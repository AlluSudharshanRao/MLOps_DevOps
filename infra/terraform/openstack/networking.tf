# Floating IPs require L3: the tenant subnet must reach the external network (e.g. "public").
# If you see: "External network ... is not reachable from subnet ...", enable create_public_router
# or attach your subnet to an existing router in Horizon (Network → Routers).

data "openstack_networking_network_v2" "external" {
  name = var.floating_ip_pool
}

data "openstack_networking_subnet_ids_v2" "project_subnets" {
  network_id = var.network_id
}

locals {
  _subnet_ids       = sort(tolist(data.openstack_networking_subnet_ids_v2.project_subnets.ids))
  project_subnet_id = var.subnet_id != "" ? var.subnet_id : local._subnet_ids[0]
}

resource "openstack_networking_router_v2" "public_router" {
  count               = var.create_public_router ? 1 : 0
  name                = "mlops-router-${var.project_id_suffix}"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "project_subnet" {
  count     = var.create_public_router ? 1 : 0
  router_id = openstack_networking_router_v2.public_router[0].id
  subnet_id = local.project_subnet_id
}
