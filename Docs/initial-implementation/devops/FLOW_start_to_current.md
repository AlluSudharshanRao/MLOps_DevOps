# End-to-End Flow (Start to Current State)

This document is the single source of truth for what we have done so far for the DevOps/Platform track, from empty setup to current status.

It includes:
- architecture and tool split
- exact command flow (Terraform + Ansible + Helm + kubectl)
- issues we hit and why fixes worked
- current status and what remains

Companion docs:
- `COMMANDS_history_and_explanations.md` -> command-first log (including troubleshooting commands)
- `RUNBOOK_chameleon_k8s_zulip.md` -> detailed early-phase infra reasoning
- `EXPLANATION_so_far.md` -> design and decision rationale
- `README_docs_guide.md` -> how to read this doc set

---

## 1) Architecture and tool flow

- **Cloud**: Chameleon `KVM@TACC` (OpenStack)
- **IaC**: Terraform in `infra/terraform/openstack/`
- **CaC**: Ansible in `infra/ansible/`
- **Cluster**: single-node `k3s` on VM
- **Apps**:
  - MLflow from `k8s/platform/mlflow/`
  - Zulip via Helm chart from `docker-zulip/helm/zulip`

High-level flow:
1. Reserve resources on Chameleon (lease/reservation).
2. Terraform creates VM + networking + floating IP.
3. SSH to VM.
4. Ansible installs k3s and deploys base manifests.
5. Ansible deploys Zulip Helm release.
6. Verify pods/services and create Zulip org.

---

## 2) Chameleon prerequisites used

- Lease: `Devops_proj15`
- Reservation UUID (instance reservation): `07dc4b8c-3b0c-4af4-b23d-987a70891356`
- Project network: `Devops_proj15`
- Network ID: `acfc7410-cef1-4955-b4d3-147df3ecfea8`
- VM name: `mlops-k8s-proj15`
- Floating IP observed: `129.114.26.117`
- SSH user: `cc`

---

## 3) Terraform phase (OpenStack provisioning)

Working directory:

```bash
cd infra/terraform/openstack
```

Auth approach used: OpenStack **application credentials**.

### 3.1 Environment variables used (PowerShell example)

```powershell
$env:OS_AUTH_URL="https://kvm.tacc.chameleoncloud.org:5000/v3"
$env:OS_REGION_NAME="KVM@TACC"
$env:OS_INTERFACE="public"
$env:OS_IDENTITY_API_VERSION="3"
$env:OS_AUTH_TYPE="v3applicationcredential"
$env:OS_APPLICATION_CREDENTIAL_ID="<id>"
$env:OS_APPLICATION_CREDENTIAL_SECRET="<secret>"

$env:TF_VAR_application_credential_id="<id>"
$env:TF_VAR_application_credential_secret="<secret>"
```

### 3.2 Terraform run commands

```bash
terraform init
terraform plan
terraform apply
```

Common output checks:

```bash
terraform output
terraform output -raw ansible_inventory_ini
```

### 3.3 Key implementation details

- VM uses reservation UUID as flavor:
  - `flavor_id = blazar_reservation_id`
- Floating IP association uses Neutron port data source:
  - `data.openstack_networking_port_v2 ...`
- Router + router interface enabled (when needed) so external network is reachable.

---

## 4) SSH verification

```bash
ssh -i sa9876.pem cc@129.114.26.117
```

Result observed: successful login to Ubuntu 24.04 VM.

---

## 5) Ansible phase (k3s + platform deploy)

Working directory:

```bash
cd infra/ansible
```

Inventory used:

```ini
[chameleon]
129.114.26.117

[chameleon:vars]
ansible_user=cc
ansible_ssh_private_key_file=/mnt/c/Users/rithw/OneDrive/Desktop/cmder/sa9876.pem
```

### 5.1 Install k3s

```bash
ansible-playbook -i inventory.ini playbooks/k3s_install.yml
```

### 5.2 Deploy namespaces + MLflow manifests

```bash
ansible-playbook -i inventory.ini playbooks/deploy_platform.yml
```

This copies `k8s/` manifests to VM path:
- `/opt/mlops_project/k8s/...`

---

## 6) Zulip Helm preparation and deploy

### 6.1 On VM (`cc@mlops-k8s-proj15`)

Clone chart source:

```bash
git clone https://github.com/zulip/docker-zulip.git
cd docker-zulip/helm/zulip
```

Install Helm 3 (done on VM):

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
helm version
```

Download chart dependencies:

```bash
helm dependency update
```

Create secrets values file:

```bash
cp ~/docker-zulip/helm/zulip/values-local.yaml.example ~/values-secret.yaml
nano ~/values-secret.yaml
```

Important rules for `~/values-secret.yaml`:
- quote secret values, especially numeric-looking passwords
- keep `memcached`, `rabbitmq`, `redis`, `postgresql` as top-level keys
- only `environment` is nested under `zulip`

### 6.2 From laptop/WSL (Ansible controller)

```bash
cd /mnt/c/Users/rithw/OneDrive/Desktop/MLOps_Project/infra/ansible
ansible-playbook -i inventory.ini playbooks/deploy_zulip.yml \
  -e zulip_chart_dir=/home/cc/docker-zulip/helm/zulip \
  -e project_id_suffix=proj15 \
  -e zulip_values_file=/opt/mlops_project/k8s/zulip/values-chameleon.yaml \
  -e zulip_secret_values_file=/home/cc/values-secret.yaml
```

Latest successful result:
- `PLAY RECAP ... failed=0`

---

## 7) Runtime verification commands used

Watch Zulip namespace pods:

```bash
kubectl get pods -n zulip -w
```

Observed final state:
- `zulip-proj15-0` -> `1/1 Running`
- memcached/postgresql/rabbitmq/redis pods running

Create org link:

```bash
kubectl exec -n zulip zulip-proj15-0 -c zulip -- runuser -u zulip -- \
  /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

Generated URL pattern observed:
- `https://129.114.26.117.nip.io/new/<token>`

---

## 8) Access and forwarding commands used

### 8.1 Correct service port-forward syntax

```bash
kubectl port-forward -n zulip svc/zulip-proj15 8080:80
```

(Previous invalid command used `127.0.0.1:8080:80`, which is not accepted in that position.)

Optional explicit bind:

```bash
kubectl port-forward -n zulip --address 127.0.0.1 svc/zulip-proj15 8080:80
```

### 8.2 SSH local tunnel from Windows

If using Cmder/Windows OpenSSH, key must be passed explicitly:

```bash
ssh -i C:\Users\rithw\OneDrive\Desktop\cmder\sa9876.pem -L 8080:127.0.0.1:8080 -N cc@129.114.26.117
```

---

## 9) Issues encountered and fixes (chronological)

1. **Terraform scheduler hints / no valid host**
   - Fix: use reservation UUID as `flavor_id`.

2. **Floating IP external network unreachable**
   - Fix: router + subnet interface.

3. **Subnet gateway/allocation pool conflicts**
   - Fix: non-overlapping gateway/pool (e.g. gateway `.254`).

4. **FIP association issues**
   - Fix: use floating IP `.address`, and lookup VM port via Neutron data source.

5. **Ansible environment issues on Windows**
   - Fix: run in WSL clean venv with compatible `ansible-core`.

6. **Wrong chart path confusion**
   - Correct path: `docker-zulip/helm/zulip` (not `kubernetes/chart/zulip`).

7. **Helm schema/value parse failures**
   - Fixes:
     - remove malformed YAML content / stale VM file
     - quote secret strings
     - correct YAML indentation/top-level keys

8. **Raw HTML Zulip page (no styling)**
   - Usually host/scheme/static asset mismatch while using mixed access methods.
   - Use consistent host (`SETTING_EXTERNAL_HOST`) and access path.

---

## 10) Current status (where we are now)

- Terraform provisioning: complete and validated.
- VM + floating IP + SSH: working.
- k3s install: complete.
- MLflow deploy: complete (pod/PVC previously verified).
- Zulip Helm deploy: successful (`failed=0`).
- Zulip pods: running.
- Org creation link generated and reachable.
- Remaining: finalize stable browser access mode (host consistency for static assets), complete org setup UI, collect demo evidence/screenshots, and update requirement docs.

---

## 11) Start-to-current command quick sheet

```bash
# Terraform
cd infra/terraform/openstack
terraform init
terraform plan
terraform apply
terraform output -raw ansible_inventory_ini

# SSH
ssh -i sa9876.pem cc@129.114.26.117

# Ansible
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/k3s_install.yml
ansible-playbook -i inventory.ini playbooks/deploy_platform.yml

# VM prep for Zulip
git clone https://github.com/zulip/docker-zulip.git
cd docker-zulip/helm/zulip
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
helm dependency update
cp ~/docker-zulip/helm/zulip/values-local.yaml.example ~/values-secret.yaml
nano ~/values-secret.yaml

# Deploy Zulip
cd /mnt/c/Users/rithw/OneDrive/Desktop/MLOps_Project/infra/ansible
ansible-playbook -i inventory.ini playbooks/deploy_zulip.yml \
  -e zulip_chart_dir=/home/cc/docker-zulip/helm/zulip \
  -e project_id_suffix=proj15 \
  -e zulip_values_file=/opt/mlops_project/k8s/zulip/values-chameleon.yaml \
  -e zulip_secret_values_file=/home/cc/values-secret.yaml

# Verify + create org link
kubectl get pods -n zulip -w
kubectl exec -n zulip zulip-proj15-0 -c zulip -- runuser -u zulip -- \
  /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

