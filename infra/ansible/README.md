# Ansible (CaC): Kubernetes + cluster services/apps

This directory is the **configuration-as-code** counterpart to Terraform IaC.

## What this does

- Installs a **single-node k3s** cluster on your Chameleon VM (good enough for the DevOps initial milestone).
- Deploys **shared platform services** (MLflow) with **persistent storage**.
- Deploys **Zulip** on Kubernetes using the upstream Helm chart from [docker-zulip](https://github.com/zulip/docker-zulip).

## Prereqs on your laptop or jump host

- **`ansible-core`** installed in a **clean environment** (recommended: a dedicated `venv`, not Conda `base` mixed with `pip install ansible`)
- SSH access to the VM (keypair from Chameleon)
- `helm` optional on the controller: the Zulip playbook installs Helm 3 on the target VM if missing
- Optional: `kubectl` (helpful for verifying)

## Inventory

Create `inventory.ini` (do **not** commit secrets):

```ini
[chameleon]
<FLOATING_IP>

[chameleon:vars]
ansible_user=cc
ansible_ssh_private_key_file=~/.ssh/YOUR_KEY
```

Tip: after `terraform apply` in `infra/terraform/openstack/`, you can print an inventory stub:

```bash
terraform output -raw ansible_inventory_ini
```

## Run

1) Install k3s:

```bash
ansible-playbook -i inventory.ini playbooks/k3s_install.yml
```

2) Deploy MLflow (PVC-backed) and namespaces:

```bash
ansible-playbook -i inventory.ini playbooks/deploy_platform.yml
```

3) **Zulip — one-time prep on the VM** (SSH as `cc`; Ansible runs Helm on the **VM**, so paths below are **on the VM**, not your laptop):

```bash
# Chart source (if you do not already have it)
git clone --depth 1 https://github.com/zulip/docker-zulip.git ~/docker-zulip

# Secrets file (never commit). Pick either:
cp ~/docker-zulip/helm/zulip/values-local.yaml.example ~/values-secret.yaml
# …or, after step 2:  cp /opt/mlops_project/k8s/zulip/values-secret.yaml.example ~/values-secret.yaml
nano ~/values-secret.yaml   # set SETTING_EXTERNAL_HOST, admin email, SECRETS_secret_key, DB passwords
```

Use a hostname you can open in a browser. For a floating IP only, a common pattern is **nip.io**, e.g. `129.114.26.117.nip.io` for IP `129.114.26.117`, and set `SETTING_EXTERNAL_HOST` to that exact string.

4) Deploy Zulip chart **from your laptop** (WSL/Linux with Ansible), with **VM paths**:

```bash
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/deploy_zulip.yml \
  -e zulip_chart_dir=/home/cc/docker-zulip/helm/zulip \
  -e project_id_suffix=proj15 \
  -e zulip_values_file=/opt/mlops_project/k8s/zulip/values-chameleon.yaml \
  -e zulip_secret_values_file=/home/cc/values-secret.yaml
```

Adjust `zulip_chart_dir` if you cloned somewhere other than `~/docker-zulip`. Step **2** must have run first so `/opt/mlops_project/k8s/zulip/values-chameleon.yaml` exists on the VM.

`values-secret.yaml` (on the VM as `~/values-secret.yaml` in the example) must stay **out of Git**.

Alternative without a chart clone on the VM: on the VM run `helm install ... oci://ghcr.io/zulip/helm-charts/zulip -f ...` yourself; this playbook expects a local chart directory for `helm dependency update`.

## Troubleshooting

### `ModuleNotFoundError: No module named 'ansible.module_utils.six.moves'` (during Gathering Facts)

Your **control node** Ansible install is incomplete or conflicting (common with **Conda `base` + pip**). Remote modules are built from that install, so every task can fail the same way.

**Fix:** use a dedicated virtualenv and reinstall `ansible-core`:

```bash
python3 -m venv ~/.venv-ansible-mlops
source ~/.venv-ansible-mlops/bin/activate
pip install -U pip ansible-core
which ansible-playbook
ansible-playbook --version
```

Run all playbooks with `source ~/.venv-ansible-mlops/bin/activate` first. Avoid running `ansible-playbook` from an environment where `pip show ansible-core` is missing or broken.

### SSH: `Permissions ... for '...pem' are too open` (WSL)

If the key lives under `/mnt/c/...`, `chmod` often cannot lock it down. Copy the key into the Linux home directory and point `ansible_ssh_private_key_file` at that copy (`chmod 600`). See comments in `inventory.example.ini`.

