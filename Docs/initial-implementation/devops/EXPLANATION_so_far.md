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

---

## 10) What "success" looked like operationally

Deployment succeeded when:
- Ansible `deploy_zulip.yml` completed with `failed=0`,
- pods in namespace `zulip` stabilized,
- `zulip-proj15-0` became `1/1 Running`,
- organization creation link command executed successfully.

This confirms chart dependencies, DB/cache/broker services, app startup, and management command path are functional.

---

## 11) Why browser rendering looked plain (unstyled page)

The observed plain HTML page indicates static assets were not loading consistently. In this setup that usually comes from host/scheme inconsistency:
- `SETTING_EXTERNAL_HOST` set to one hostname,
- browser opened through another route (raw IP, localhost tunnel, or mismatched scheme/port).

Operational rule:
- choose one stable access path and align it with `SETTING_EXTERNAL_HOST`.

For demos, either:
- use nip.io host + reachable NodePort consistently, or
- use a tunnel workflow that still preserves host consistency.

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
- k3s installation via Ansible.
- MLflow deployment via platform manifests.
- Zulip deployment via Helm (`docker-zulip/helm/zulip`) through Ansible.
- Zulip runtime readiness and org-link generation.
- Documentation refresh under `Docs/initial-implementation/devops/`.

In progress / remaining:
- finalize single consistent browser access path for polished UI behavior,
- finish organization setup flow in browser,
- collect measured CPU/memory evidence (`kubectl top`) and fill right-sizing table,
- capture required demonstration videos.

---

## 14) Why this implementation is a solid milestone baseline

This work is now a valid baseline because it demonstrates:
- reproducibility (IaC/CaC in repo),
- correct cloud-to-cluster dependency ordering,
- successful deployment of both shared platform service (MLflow) and target open-source product (Zulip),
- operational troubleshooting discipline with documented root causes and fixes.

In short, we have moved from "infrastructure bootstrap" to "running platform + product", with only validation hardening and demo/evidence packaging left.

