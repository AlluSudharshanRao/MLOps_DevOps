# DevOps Runbook (historical base): Chameleon KVM@TACC → Terraform IaC → VM + Floating IP

This runbook documents the early, foundational bring-up phase (Terraform + networking + SSH) for the project’s DevOps/Platform initial implementation.

It is intentionally detailed so another teammate (or course staff) can reproduce the environment.

For the continuously updated full flow and command history, use:
- `FLOW_start_to_current.md`
- `COMMANDS_history_and_explanations.md`
- `EXPLANATION_so_far.md`

Historical snapshot note:
- This file preserves the original early-phase sequence and debugging context.
- Some "next steps" listed below were completed later; refer to `FLOW_start_to_current.md` for current completion status.

## Scope (what’s completed)

- **Chameleon lease/reservation** on `KVM@TACC` for **1× `m1.xxlarge`** instance.
- **Terraform IaC** created:
  - a VM bound to the **Blazar instance reservation**
  - networking required for floating IPs (router + interface, as needed)
  - a floating IP
  - floating IP association to the VM’s Neutron port
- **SSH connectivity** verified to the floating IP.

## Scope (historical "next" items at time of writing)

- Install Kubernetes (k3s) via **Ansible CaC** (`infra/ansible/playbooks/k3s_install.yml`)
- Deploy namespaces + MLflow (`infra/ansible/playbooks/deploy_platform.yml`)
- Deploy Zulip Helm chart from `zulip/docker-zulip` (`infra/ansible/playbooks/deploy_zulip.yml`)

## Target environment

- **Site**: `KVM@TACC`
- **Image**: `CC-Ubuntu24.04`
- **Reserved flavor**: `m1.xxlarge` via a Blazar lease reservation
- **Network**: project network `Devops_proj15` (UUID recorded below)

## Key IDs and values used (project-specific)

These are the values that were observed/used in the successful bring-up.

- **Lease name**: `Devops_proj15`
- **Lease status**: `ACTIVE`
- **Blazar reservation id** (instance reservation UUID):
  - `07dc4b8c-3b0c-4af4-b23d-987a70891356`
- **OpenStack project id**:
  - `89f528973fea4b3a981f9b2344e522de`
- **Project network name**: `Devops_proj15`
- **Project network id**:
  - `acfc7410-cef1-4955-b4d3-147df3ecfea8`
- **Provisioned VM name (Terraform)**:
  - `mlops-k8s-proj15`
- **Provisioned VM instance id (Terraform output)**:
  - `c95341ba-5889-4881-8e78-8ea0b0018c34`
- **Floating IP (Terraform output)**:
  - `129.114.26.117`

## Repository structure used for DevOps (IaC/CaC split)

- **IaC (Terraform)**: `infra/terraform/openstack/`
  - Creates OpenStack resources (VM, router/interface if enabled, floating IP, association)
- **CaC (Ansible)**: `infra/ansible/`
  - Installs/configures Kubernetes and deploys services/apps
- **K8s manifests committed to Git**: `k8s/`
  - Namespaces, MLflow manifests, Zulip values

## Files created/modified and why (exact)

### Terraform IaC: `infra/terraform/openstack/`

- `providers.tf`
  - **Why**: Chameleon KVM@TACC uses SSO/OIDC frequently; password auth can be painful.
  - **What changed**: Provider now supports **application credentials**:
    - `application_credential_id`
    - `application_credential_secret`
  - **Security**: secrets must be provided via environment variables:
    - `TF_VAR_application_credential_secret`

- `variables.tf`
  - **Added/updated**:
    - `blazar_reservation_id`: **instance reservation UUID** used as `flavor_id` when set
    - `create_public_router`: creates a router and attaches the subnet so floating IPs work
    - `subnet_id`: optional override when multiple subnets exist or auto-detect is wrong
    - `application_credential_id` / `application_credential_secret` (preferred auth)

- `compute.tf`
  - **VM creation**:
    - Uses `flavor_id = blazar_reservation_id` when set.
      - This matches Horizon behavior where the lease reservation is exposed as:
        - `Flavor Name: reservation:<uuid>`
        - `Flavor ID: <uuid>`
    - Uses `flavor_name` only when `blazar_reservation_id` is empty.
  - **Floating IP allocation**:
    - `openstack_networking_floatingip_v2.fip`
  - **Floating IP association**:
    - Uses `openstack_networking_floatingip_associate_v2`
    - Important: provider expects the **floating IP address** (`.address`), not `.id`.
    - Port ID is discovered via:
      - `data.openstack_networking_port_v2.k8s_node_port`
      - Reason: `openstack_compute_instance_v2.network[0].port` was `null` in state.
  - **Dependency ordering**:
    - Uses static `depends_on = [openstack_networking_router_interface_v2.project_subnet]`
    - Reason: Terraform requires `depends_on` be a static list (no conditional expression).

- `networking.tf`
  - **Why**: Floating IP association failed with:
    - “External network … is not reachable from subnet …”
  - **Fix**: Create a router with external gateway and attach the project subnet.
    - `openstack_networking_router_v2.public_router`
    - `openstack_networking_router_interface_v2.project_subnet`
  - **Subnet selection**:
    - Uses `data.openstack_networking_subnet_ids_v2` for `network_id`
    - Chooses the first subnet (sorted) unless `subnet_id` is explicitly provided.

- `outputs.tf`
  - **Outputs**:
    - `floating_ip`
    - `instance_id`
    - `instance_name`
    - `ansible_inventory_ini` (convenience snippet for `infra/ansible/inventory.ini`)

- `terraform.tfvars` (local, gitignored)
  - **What it contains**: project-specific values (no secrets committed)
  - **Important**: do not commit this file.

### Ansible CaC: `infra/ansible/` (prepared, not yet executed in this runbook)

- `infra/ansible/playbooks/k3s_install.yml`
  - Installs single-node k3s and writes kubeconfig to `/home/<user>/.kube/config`.
- `infra/ansible/playbooks/deploy_platform.yml`
  - Applies `k8s/base/namespaces.yaml` and `k8s/platform/mlflow/` (kustomize).
- `infra/ansible/playbooks/deploy_zulip.yml`
  - Installs Zulip via Helm chart from upstream `docker-zulip`.

### K8s manifests (prepared for later)

- `k8s/base/namespaces.yaml`
- `k8s/platform/mlflow/` (PVC + Deployment + Service)
- `k8s/zulip/values-chameleon.yaml` (non-secret Helm overrides for k3s / storage / NodePort)
- `k8s/zulip/values-secret.yaml.example` → copy to local `values-secret.yaml` (gitignored)

## Authentication: application credentials (required for Terraform in this setup)

Chameleon SSO accounts may not have a “classic” OpenStack password flow. We used **application credentials**.

**Horizon path**: `Identity → Application Credentials → Create Application Credential`

**Important**: If a credential secret is ever pasted into a chat/log, treat it as compromised:
delete it and create a new one.

Recommended PowerShell env vars (example; do not store in Git):

```powershell
$env:OS_AUTH_URL="https://kvm.tacc.chameleoncloud.org:5000/v3"
$env:OS_REGION_NAME="KVM@TACC"
$env:OS_INTERFACE="public"
$env:OS_IDENTITY_API_VERSION="3"
$env:OS_AUTH_TYPE="v3applicationcredential"
$env:OS_APPLICATION_CREDENTIAL_ID="<id>"
$env:OS_APPLICATION_CREDENTIAL_SECRET="<secret>"

# Terraform also accepts TF_VAR_*
$env:TF_VAR_application_credential_id="<id>"
$env:TF_VAR_application_credential_secret="<secret>"
```

## Lease reservation: how it was bound to Terraform VM

The lease’s instance reservation UUID was used as the **Nova flavor ID**:

- `blazar_reservation_id = "07dc4b8c-3b0c-4af4-b23d-987a70891356"`
- Terraform sets:
  - `flavor_id = blazar_reservation_id`
  - (instead of `flavor_name = "m1.xxlarge"` + scheduler hints)

Reason: On Chameleon, the reservation shows up as `reservation:<uuid>` flavor in Horizon, and scheduling succeeds when you use that reservation “flavor”.

## Networking and floating IP lessons learned

### Symptom: FIP associate failed with “external network not reachable”

Meaning: the project subnet was not connected to the external network (e.g. `public`) via a router.

Fix options:

- **Terraform-managed router**: keep `create_public_router = true` (default)
- **Horizon-managed router**: create router + attach subnet + set `create_public_router = false`

### Symptom: router interface failed “Subnet … must have a gateway IP”

Meaning: the subnet had “no gateway” (gateway disabled). Neutron refuses to attach such a subnet to a router.

Resolution: set a valid gateway IP and adjust the allocation pool to not overlap:

- Example pattern:
  - gateway: `192.168.1.254`
  - allocation pool: `192.168.1.2 - 192.168.1.253`

### Symptom: router interface failed “IP address 192.168.1.1 already allocated”

Meaning: `.1` was already claimed by an existing port, but Neutron tried to use it for router interface.

Resolution: use a different gateway IP (e.g. `.254`) and ensure `.1` is not used as the gateway.

## Successful Terraform apply result (proof)

Terraform output showed:

- `floating_ip = "129.114.26.117"`
- `instance_name = "mlops-k8s-proj15"`

And SSH succeeded:

```bash
ssh -i sa9876.pem cc@129.114.26.117
```

Login banner confirmed:

- Ubuntu 24.04 LTS
- Hostname: `mlops-k8s-proj15`

## What to do next (checklist)

1. (Optional) From the VM: `sudo apt-get update`
2. Create `infra/ansible/inventory.ini` with the floating IP and SSH key.
3. Run:
   - `ansible-playbook ... k3s_install.yml`
   - `ansible-playbook ... deploy_platform.yml`
4. Clone [docker-zulip](https://github.com/zulip/docker-zulip), run `helm dependency update` in `helm/zulip/`, create `values-secret.yaml` from `k8s/zulip/values-secret.yaml.example`, then run `deploy_zulip.yml` with `-e zulip_chart_dir=.../docker-zulip/helm/zulip` (see `infra/ansible/README.md`).
5. Start collecting right-sizing evidence:
   - `kubectl top pod -A`
6. Fill:
   - `docs/initial-implementation/devops/infrastructure-requirements.md`

