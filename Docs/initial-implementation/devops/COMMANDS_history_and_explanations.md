# Command History and Explanations (Terraform + Ansible + Helm + kubectl)

This document captures the command flow we used in practice, including important troubleshooting commands and why they were needed.

Use this with:
- `FLOW_start_to_current.md` for the end-to-end sequence.
- `RUNBOOK_chameleon_k8s_zulip.md` for detailed background on early infra bring-up.

---

## 1) OpenStack auth and Terraform (IaC)

Working directory:

```bash
cd infra/terraform/openstack
```

PowerShell env variables used for application-credential auth:

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

Primary Terraform commands used:

```bash
terraform init
terraform plan
terraform apply
terraform output
terraform output -raw ansible_inventory_ini
```

Why these mattered:
- Reservation scheduling worked only when VM used reservation UUID as `flavor_id`.
- Floating IP required L3 router path (router + subnet interface).
- FIP association required VM Neutron `port_id` via data source lookup.

---

## 2) SSH and base verification

```bash
ssh -i sa9876.pem cc@129.114.26.117
```

We used this to confirm:
- VM reachable from public Internet.
- OS and host are correct before Ansible rollout.

---

## 3) Ansible (CaC): k3s + platform services

Working directory:

```bash
cd infra/ansible
```

**Controller setup (WSL/Linux):** use a dedicated venv so `ansible-core` is complete:

```bash
python3 -m venv ~/.venv-ansible-mlops
source ~/.venv-ansible-mlops/bin/activate
pip install -U pip ansible-core
```

**Inventory:** SSH keys on `/mnt/c/...` often stay world-readable → OpenSSH refuses them. Copy `.pem` to `~/.ssh/`, `chmod 600`, set `ansible_ssh_private_key_file=~/.ssh/...` in `inventory.ini`.

Install k3s:

```bash
ansible-playbook -i inventory.ini playbooks/k3s_install.yml
```

Deploy namespaces + MLflow manifests (includes **MLflow Ingress**):

```bash
ansible-playbook -i inventory.ini playbooks/deploy_platform.yml
```

Why this step mattered:
- Copies `k8s/` manifests to `/opt/mlops_project/k8s/` on VM.
- Applies `kubectl apply -k` for MLflow (Deployment, PVC, Service, **Ingress**).
- Ensures `values-chameleon.yaml` exists on VM for Helm.

---

## 4) Zulip chart preparation on VM

On VM (`cc@mlops-k8s-proj15`):

```bash
git clone https://github.com/zulip/docker-zulip.git
cd docker-zulip/helm/zulip
```

Install Helm on VM when missing:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
helm version
```

Fetch chart dependencies:

```bash
helm dependency update
```

Create local secrets values file:

```bash
cp ~/docker-zulip/helm/zulip/values-local.yaml.example ~/values-secret.yaml
nano ~/values-secret.yaml
```

Critical YAML rules used:
- Keep `memcached`, `rabbitmq`, `redis`, `postgresql` as top-level keys.
- Keep only `environment` under `zulip`.
- Quote passwords as strings (especially numeric-looking values).

---

## 5) Zulip deploy command from laptop/WSL

```bash
cd /mnt/c/Users/rithw/OneDrive/Desktop/MLOps_Project/infra/ansible
ansible-playbook -i inventory.ini playbooks/deploy_zulip.yml \
  -e zulip_chart_dir=/home/cc/docker-zulip/helm/zulip \
  -e project_id_suffix=proj15 \
  -e zulip_values_file=/opt/mlops_project/k8s/zulip/values-chameleon.yaml \
  -e zulip_secret_values_file=/home/cc/values-secret.yaml
```

Successful endpoint:
- `PLAY RECAP ... failed=0`

---

## 6) TLS Secret for Ingress (on VM)

After generating `tls.crt` / `tls.key` (see `RUNBOOK_zulip_access_after_setup.md`):

```bash
kubectl create secret tls chameleon-nip-tls -n zulip --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls chameleon-nip-tls -n ml-platform --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -
```

---

## 7) Runtime verification commands

```bash
kubectl get pods -n zulip -w
kubectl get ingress -A
kubectl describe ingress -n zulip zulip-proj15
kubectl get svc -n zulip
kubectl get pvc -n zulip
```

**From laptop (Windows):** `Test-NetConnection -ComputerName <FIP> -Port 443` (and **80**).

Stable org creation (when enabled): open **`https://zulip.<fip>.nip.io/new/`**.

Optional CLI single-use link:

```bash
kubectl exec -n zulip zulip-proj15-0 -c zulip -- runuser -u zulip -- \
  /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

Verify env after **`helm upgrade`**:

```bash
kubectl exec -n zulip zulip-proj15-0 -c zulip -- env | grep -E 'SETTING_EXTERNAL|LOADBALANCER|OPEN_REALM'
kubectl exec -n zulip zulip-proj15-0 -c zulip -- grep -E '^\[loadbalancer\]|^ips' /etc/zulip/zulip.conf
```

---

## 8) Legacy access (optional)

Port-forward (debug only; production path is **Ingress :443**):

```bash
kubectl port-forward -n zulip svc/zulip-proj15 8080:80
```

---

## 9) Important failed commands and what they taught us

Wrong chart path attempt:

```bash
-e zulip_chart_dir=/path/to/docker-zulip/kubernetes/chart/zulip
```

Fix:
- Correct path is `docker-zulip/helm/zulip`.

Wrong copy path from inside chart dir:

```bash
cp k8s/zulip/values-secret.yaml.example /path/to/values-secret.yaml
```

Fix:
- Use chart-local template (`values-local.yaml.example`) or repo copy at `/opt/mlops_project/k8s/zulip/...` after `deploy_platform.yml`.

Wrong port-forward form:

```bash
kubectl port-forward -n zulip svc/zulip-proj15 127.0.0.1:8080:80
```

Fix:
- `kubectl port-forward -n zulip svc/zulip-proj15 8080:80`

Schema/YAML errors encountered:
- `cannot unmarshal number into map[string]interface{}` -> malformed values YAML.
- `rabbitmq/redis password got number, want string` -> numeric values not quoted.
- `could not find expected ':'` -> YAML syntax/indent issue in `values-secret.yaml`.

Ansible / runtime:
- `ModuleNotFoundError: ansible.module_utils.six.moves` -> reinstall **`ansible-core`** in a clean **venv** (not broken Conda mix).
- `Permissions ... pem are too open` -> key under **`~/.ssh/`** with **`chmod 600`**.
- Zulip **`ProxyMisconfigurationError`** -> set **`LOADBALANCER_IPS`** env (e.g. `10.42.0.0/16`) so **`zulip.conf`** trusts Traefik; confirm with `env` + `grep ips /etc/zulip/zulip.conf`.
- Traefik **404** on realm URL -> **`SETTING_EXTERNAL_HOST`** must match Ingress (**`zulip.<ip>.nip.io`**); **`helm upgrade`** + pod restart.
- **`/new/`** “link required” -> **`SETTING_OPEN_REALM_CREATION: "True"`** in **`~/values-secret.yaml`** (or equivalent), then **`helm upgrade`**.

---

## 10) Current “known-good” validation commands

```bash
kubectl get pods -n zulip
kubectl get ingress -A
kubectl get secret chameleon-nip-tls -n zulip
curl -skI -H "Host: zulip.129.114.26.117.nip.io" https://127.0.0.1/
```

Status reached:
- `zulip-proj15-0` `1/1 Running`; **HTTPS** UI and org creation work in browser.
- MLflow UI at **`https://mlflow.<fip>.nip.io/`**.

