# DevOps explanation (so far): what we did, why it worked, and what we learned

This document explains the engineering reasoning behind the DevOps/Platform implementation completed so far.

Use with:
- `FLOW_start_to_current.md` for timeline and flow.
- `COMMANDS_history_and_explanations.md` for command-by-command history.
- `RUNBOOK_chameleon_k8s_zulip.md` for detailed early infra notes.
- `README_docs_guide.md` for doc navigation.

---

## 1) Project context and target outcome

For the initial implementation milestone, DevOps/Platform needs to deliver:
- reproducible infrastructure provisioning on Chameleon (IaC),
- reproducible cluster/application deployment (CaC),
- durable shared platform services (MLflow),
- deployment of the open-source product (Zulip),
- operational evidence and right-sizing inputs.

The key success criterion is not just "it ran once", but "a teammate can re-run this from repo artifacts and get the same environment."

---

## 2) Why this tool split was chosen

We intentionally followed:
- **Terraform** for cloud resource lifecycle (`infra/terraform/openstack/`),
- **Ansible** for node and workload configuration (`infra/ansible/`),
- Kubernetes manifests/values in `k8s/`.

This aligns with the course IaC/CaC separation and keeps responsibilities clear:
- cloud networking/VM concerns in Terraform,
- cluster/workload concerns in Ansible + Helm + kubectl.

---

## 3) OpenStack authentication: why application credentials

Chameleon KVM@TACC commonly uses SSO/OIDC flows, which are inconvenient for non-interactive automation. We switched to OpenStack application credentials because they are:
- script-friendly,
- revocable,
- scoped to project operations,
- easier to keep out of code (environment variables).

This removed a major source of flaky auth behavior during Terraform runs.

---

## 4) Compute reservation: why `flavor_id = reservation_uuid`

### Problem
Initial attempts used generic flavor (`m1.xxlarge`) plus reservation hints. Scheduling failed with "No valid host".

### Insight
In Horizon, the lease appears as a reservation-backed flavor:
- name like `reservation:<uuid>`,
- flavor id equal to reservation UUID.

### Fix
Set VM `flavor_id` directly to the reservation UUID (`blazar_reservation_id`) instead of relying on hints.

### Why this is correct
It matches what Horizon successfully schedules and removes ambiguity from scheduler-hint behavior.

---

## 5) Networking path: why router + interface were mandatory

### Problem
Floating IP association failed with "external network is not reachable from subnet".

### Root cause
The tenant subnet had no complete L3 path to the public network.

### Fix
Add:
- router with external gateway,
- router interface attached to the project subnet.

### Additional subnet corrections
We also handled Neutron constraints:
- subnet must have a valid gateway for router attachment,
- gateway and allocation pool must not overlap,
- gateway IP must not already be consumed.

These were essential plumbing fixes before any Kubernetes or app work could succeed externally.

---

## 6) Floating IP association: why Neutron port data source was needed

### Problem
`openstack_compute_instance_v2.network[0].port` was null in state.

### Fix
Query Neutron port explicitly using:
- server/device id,
- network id.

Then bind floating IP to that resolved port id.

### Why this is robust
It avoids provider-state assumptions and asks Neutron directly for the authoritative port mapping.

---

## 7) CaC rollout: k3s and base platform

After VM/network were stable:
1. `k3s_install.yml` installed single-node k3s.
2. `deploy_platform.yml` copied `k8s/` into `/opt/mlops_project/k8s/` and applied namespaces + MLflow.

Result:
- cluster became operational,
- MLflow workload and PVC were deployed,
- repo manifests became the source for platform workloads on the VM.

---

## 8) Zulip deployment architecture choices

We separated:
- **app source** (`zulip/zulip`) for product code understanding,
- **deployment chart** (`zulip/docker-zulip`) for Kubernetes install.

This is intentional: running Zulip in Kubernetes is chart-driven operationally, not by building directly from app repo in this milestone.

---

## 9) Zulip Helm deployment: key pitfalls and fixes

### 9.1 Chart path mismatch
- Wrong assumption: `kubernetes/chart/zulip`.
- Correct path: `docker-zulip/helm/zulip`.

### 9.2 Helm availability on target
Helm was missing on VM initially. We ensured the playbook checks/install Helm 3 on target if absent.

### 9.3 Values file location confusion (controller vs VM)
Ansible executes Helm on VM; therefore:
- `zulip_chart_dir`, `zulip_values_file`, `zulip_secret_values_file` must be VM paths.

### 9.4 YAML and schema issues in secrets
We hit several classes of failures:
- malformed YAML (syntax/indentation),
- numeric values interpreted as numbers instead of strings for chart passwords,
- wrong key nesting under `zulip`.

Fixes applied:
- quote secrets,
- keep dependency blocks as top-level (`memcached`, `redis`, `rabbitmq`, `postgresql`),
- keep only `environment` under `zulip`,
- provide improved `values-secret.yaml.example` guidance.

### 9.5 Namespace variable warning in playbook
Ansible warning for reserved variable name `namespace` was removed by renaming to `zulip_k8s_namespace`.

### 9.6 Ingress (Traefik) instead of NodePort + host nginx
We moved public access to **Kubernetes Ingress** (k3s default **Traefik**) so the course “networking/ingress” requirement is met explicitly. Zulip and MLflow use **separate nip.io subdomains** on the same floating IP (`zulip.<ip>.nip.io`, `mlflow.<ip>.nip.io`). **TLS** terminates at the Ingress using a **self-signed** Secret (`chameleon-nip-tls`) in both namespaces; browsers show a warning until the cert is trusted or replaced (e.g. Let’s Encrypt + cert-manager).

### 9.7 Reverse proxy trust (Traefik → Zulip container nginx)
Zulip runs **nginx inside the pod** and validates trusted proxy IPs via **`/etc/zulip/zulip.conf`** (`loadbalancer ips`), populated from the **`LOADBALANCER_IPS`** container environment variable in **docker-zulip’s entrypoint** — not only from Django `ZULIP_CUSTOM_SETTINGS`. Without trusting the **k3s pod CIDR** (e.g. `10.42.0.0/16`), requests from Traefik’s pod IP caused **`ProxyMisconfigurationError`** and HTTP 500. We also set **`USE_X_FORWARDED_HOST`** and **`SECURE_PROXY_SSL_HEADER`** for HTTPS termination at Traefik.

### 9.8 Hostnames and realm URLs
**`SETTING_EXTERNAL_HOST`** must match the **Ingress host** (`zulip.<ip>.nip.io`). If it stays on bare `<ip>.nip.io`, `generate_realm_creation_link` prints URLs Traefik does not route → **404**. After changing secrets, **`helm upgrade`** must run so the StatefulSet env updates (verify with `kubectl exec ... env | grep SETTING_EXTERNAL`).

### 9.9 Open organization creation (`/new/`)
For demos we enabled **`SETTING_OPEN_REALM_CREATION`** so **`https://<external-host>/new/`** works without rotating CLI tokens. Because a partial **`ZULIP_CUSTOM_SETTINGS`** block in `values-secret.yaml` can override the repo overlay, **`SETTING_OPEN_REALM_CREATION: "True"`** is also set in **`~/values-secret.yaml`** so it survives merges.

---

## 10) What "success" looked like operationally

Deployment succeeded when:
- Ansible `deploy_zulip.yml` completed with `failed=0`,
- pods in namespace `zulip` stabilized,
- `zulip-proj15-0` became `1/1 Running`,
- **Ingress** shows correct hosts and TLS,
- organization creation works in the browser (stable **`/new/`** and/or CLI link).

This confirms chart dependencies, DB/cache/broker services, app startup, proxy trust, and public HTTPS path are functional.

---

## 11) Browser “Not secure” vs broken HTTPS

With a **self-signed** Ingress certificate, Chrome labels the site **“Not secure”** because the CA is not trusted — the connection can still be **encrypted (TLS)**. That is different from “HTTPS not working” (connection timeout, wrong port, or plain HTTP). For a green lock, trust the cert locally or use **Let’s Encrypt**.

Earlier **plain HTML / missing CSS** often came from **host or scheme mismatch** (`SETTING_EXTERNAL_HOST` vs URL). The Ingress + aligned hostname removes most of that; keep **`SETTING_EXTERNAL_HOST`** equal to the Ingress **`host`**.

---

## 12) Security and repo hygiene decisions

We kept secrets out of Git by design:
- `values-secret.yaml` is local-only.
- `.gitignore` covers common secret/material files.

We also documented credential handling (rotate if exposed) and separated examples from real secrets.

---

## 13) Current state summary (as of now)

Completed:
- Terraform provisioning for VM + networking + floating IP on Chameleon.
- SSH access validation.
- k3s installation via Ansible; **Traefik Ingress** for MLflow and Zulip.
- **HTTPS** at Ingress (self-signed); OpenStack SG allows **443** (and **80**).
- MLflow + Zulip reachable at **`mlflow.<fip>.nip.io`** and **`zulip.<fip>.nip.io`**.
- Zulip **proxy/load-balancer** configuration for Traefik; **org creation** verified in browser.
- Ansible controller notes: **WSL venv** + **`~/.ssh`** key permissions (see `infra/ansible/README.md`).
- Documentation under `Docs/initial-implementation/devops/` updated for the above.

In progress / remaining:
- measured CPU/memory evidence (`kubectl top`) in **`infrastructure-requirements.md`**,
- demonstration videos per course rubric,
- LLM-assisted commit disclosure where required,
- joint **containers-matrix** completion with teammates.

---

## 14) Why this implementation is a solid milestone baseline

This work is now a valid baseline because it demonstrates:
- reproducibility (IaC/CaC in repo),
- correct cloud-to-cluster dependency ordering,
- **Kubernetes Ingress + TLS** for both shared platform (MLflow) and product (Zulip),
- operational troubleshooting discipline (proxy trust, hostname alignment, Ansible env, security groups).

Remaining effort is mostly **evidence and demos**, not core bring-up.

