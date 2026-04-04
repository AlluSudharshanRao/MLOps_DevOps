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
- **Ingress / TLS**: k3s default **Traefik**; **Ingress** resources for MLflow and Zulip; TLS Secret **`chameleon-nip-tls`** (self-signed) in `ml-platform` and `zulip`.
- **Apps**:
  - **MLflow** from `k8s/platform/mlflow/` (Kustomize: Deployment, PVC, Service, **Ingress** → `mlflow.<floating-ip>.nip.io`).
  - **Zulip** via Helm (`docker-zulip/helm/zulip`): **ClusterIP** + **Ingress** → `zulip.<floating-ip>.nip.io`; repo overlay `k8s/zulip/values-chameleon.yaml`.

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
# WSL: use a key under ~/ssh with chmod 600 — OpenSSH rejects /mnt/c/.../*.pem (0777).
ansible_ssh_private_key_file=~/.ssh/sa9876_chameleon.pem
```

**Ansible controller:** use a dedicated **venv** with `pip install ansible-core` (Conda `base` mixes caused `ModuleNotFoundError: ansible.module_utils.six.moves`). See `infra/ansible/README.md`.

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

Applies **namespaces** and **MLflow** (including **Ingress** for MLflow).

---

## 6) TLS Secret for Ingress (VM, one-time or on cert rotation)

Self-signed cert covering **both** Ingress hostnames (SAN), then Secret in both namespaces:

```bash
cd /tmp
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=zulip.129.114.26.117.nip.io" \
  -addext "subjectAltName=DNS:zulip.129.114.26.117.nip.io,DNS:mlflow.129.114.26.117.nip.io"

kubectl create secret tls chameleon-nip-tls -n zulip --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls chameleon-nip-tls -n ml-platform --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -
```

Details: `RUNBOOK_zulip_access_after_setup.md`.

---

## 7) Zulip Helm preparation and deploy

### 7.1 On VM (`cc@mlops-k8s-proj15`)

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
- **`SETTING_EXTERNAL_HOST`** must equal the **Ingress** host (e.g. `zulip.129.114.26.117.nip.io`), **not** bare `<ip>.nip.io` — otherwise Traefik returns **404** for wrong `Host`.
- Include **`LOADBALANCER_IPS`** (e.g. `10.42.0.0/16`) and **`SETTING_OPEN_REALM_CREATION: "True"`** if you rely on the secret file for env merge (see `values-secret.yaml.example`).
- Avoid duplicating **`ZULIP_CUSTOM_SETTINGS`** in the secret unless it contains **all** needed lines; a partial block can override `values-chameleon.yaml` and drop proxy/realm settings.

### 7.2 From laptop/WSL (Ansible controller)

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

## 8) Runtime verification commands used

```bash
kubectl get pods -n zulip -w
kubectl get ingress -A
kubectl get secret chameleon-nip-tls -n zulip
kubectl get secret chameleon-nip-tls -n ml-platform
```

Observed final state:
- `zulip-proj15-0` -> `1/1 Running`
- memcached/postgresql/rabbitmq/redis pods running
- Ingress hosts: `zulip.129.114.26.117.nip.io`, `mlflow.129.114.26.117.nip.io`

**Browser (primary):**

- Zulip: `https://zulip.129.114.26.117.nip.io/` (self-signed → Chrome may show “Not secure” until cert is trusted or replaced).
- MLflow: `https://mlflow.129.114.26.117.nip.io/`
- Stable org creation (demo): `https://zulip.129.114.26.117.nip.io/new/` when `SETTING_OPEN_REALM_CREATION` is enabled.

**Optional single-use link (CLI):**

```bash
kubectl exec -n zulip zulip-proj15-0 -c zulip -- runuser -u zulip -- \
  /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

Printed URL must use the **same host** as `SETTING_EXTERNAL_HOST` (e.g. `https://zulip.129.114.26.117.nip.io/new/<token>`). After any change to `SETTING_EXTERNAL_HOST`, run **`helm upgrade`** and recycle the pod so env matches.

---

## 9) Legacy access (optional)

Earlier milestone used **NodePort + VM nginx on 8080**; current design uses **Ingress + 443**. For local debugging only:

```bash
kubectl port-forward -n zulip svc/zulip-proj15 8080:80
```

---

## 10) Issues encountered and fixes (chronological)

1. **Terraform scheduler hints / no valid host**
   - Fix: use reservation UUID as `flavor_id`.

2. **Floating IP external network unreachable**
   - Fix: router + subnet interface.

3. **Subnet gateway/allocation pool conflicts**
   - Fix: non-overlapping gateway/pool (e.g. gateway `.254`).

4. **FIP association issues**
   - Fix: use floating IP `.address`, and lookup VM port via Neutron data source.

5. **Ansible on WSL**
   - Broken Conda `ansible-core` → `ModuleNotFoundError: ansible.module_utils.six.moves`: use **`python -m venv ~/.venv-ansible-mlops`** + `pip install ansible-core`.
   - SSH key on `/mnt/c/.../*.pem` → “permissions too open”: copy key to **`~/.ssh/`** and `chmod 600`; point `inventory.ini` there.

6. **Wrong chart path confusion**
   - Correct path: `docker-zulip/helm/zulip` (not `kubernetes/chart/zulip`).

7. **Helm schema/value parse failures**
   - Fixes:
     - remove malformed YAML content / stale VM file
     - quote secret strings
     - correct YAML indentation/top-level keys

8. **Raw HTML Zulip page (no styling)**
   - Usually host/scheme/static asset mismatch while using mixed access methods.
   - Align `SETTING_EXTERNAL_HOST`, Ingress `host`, and browser URL (subdomain `zulip.<ip>.nip.io`).

9. **Browser timeout on HTTPS**
   - OpenStack security group must allow **TCP 443** (and **80** as needed). `Test-NetConnection <FIP> -Port 443`.

10. **Traefik 404 on realm link**
    - Ingress only matches **`zulip.<ip>.nip.io`**; bare **`<ip>.nip.io`** has no rule → 404.

11. **Zulip 500 `ProxyMisconfigurationError` / “Incorrect reverse proxy IP”**
    - Zulip’s **nginx** reads trusted proxies from **`zulip.conf`**, written from env **`LOADBALANCER_IPS`** (comma-separated CIDRs), not from Django-only `ZULIP_CUSTOM_SETTINGS`.
    - Trust k3s pod network (e.g. **`10.42.0.0/16`**) and ensure the var is present in the **running** pod: `kubectl exec ... env | grep LOADBALANCER`.

12. **`/new/` shows “Organization creation link required”**
    - Set **`SETTING_OPEN_REALM_CREATION: "True"`** in `zulip.environment` (recommended in **`~/values-secret.yaml`** so it is not lost when `ZULIP_CUSTOM_SETTINGS` overrides merge). **`helm upgrade`** + pod restart.

---

## 11) Current status (where we are now)

- Terraform, VM, FIP, SSH: validated.
- k3s + Traefik Ingress: **MLflow** and **Zulip** exposed on **HTTPS** (`mlflow.*` / `zulip.*` nip.io hosts); self-signed TLS at Ingress.
- Zulip: proxy/load-balancer settings applied; **website and org creation** verified in browser.
- Remaining for milestone: **`infrastructure-requirements.md`** evidence (`kubectl top`), **demo videos**, LLM disclosure on commits, joint **containers-matrix** rows for teammates.

---

## 12) Start-to-current command quick sheet

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

# TLS secrets (VM; after openssl — see §6)
kubectl create secret tls chameleon-nip-tls -n zulip --cert=/tmp/tls.crt --key=/tmp/tls.key --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls chameleon-nip-tls -n ml-platform --cert=/tmp/tls.crt --key=/tmp/tls.key --dry-run=client -o yaml | kubectl apply -f -

# Re-apply MLflow Ingress (from laptop Ansible deploy_platform copies k8s/)
# On VM: kubectl apply -k /opt/mlops_project/k8s/platform/mlflow/

# Helm upgrade Zulip after editing values-secret / values-chameleon
cd ~/docker-zulip/helm/zulip && helm upgrade --install zulip-proj15 . --namespace zulip \
  --kubeconfig "$HOME/.kube/config" \
  -f /opt/mlops_project/k8s/zulip/values-chameleon.yaml -f "$HOME/values-secret.yaml"
kubectl delete pod -n zulip zulip-proj15-0

# Verify
kubectl get ingress -A
kubectl get pods -n zulip
```

