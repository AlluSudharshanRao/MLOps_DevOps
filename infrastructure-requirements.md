# Infrastructure requirements

This document records **GPU**, **CPU and memory requests and limits**, and **persistent storage** for workloads deployed on a single-node **k3s** cluster on **Chameleon Cloud** (`KVM@TACC`). Values are taken from version-controlled manifests where applicable; **Zulip** dependencies use Helm subchart defaults unless otherwise noted. **Empirical validation** references node `mlops-k8s-proj15` (April 2026).

**GPU:** Not used. All services are scheduled on CPU-only infrastructure.

---

## 1. Compute host

The cluster runs on one OpenStack instance provisioned by Terraform (`infra/terraform/openstack/`). **Schedulable capacity** is determined by the instance **flavor** or **Blazar reservation**, not by the sum of container limits (the scheduler uses **requests** for admission).

| Dimension | Specification | Basis |
|-----------|---------------|--------|
| vCPU / memory | 16 cores; 32 863 408 Ki reported capacity (~31.3 GiB RAM) | `kubectl describe node` |
| Ephemeral storage (kubelet) | 38 691 548 Ki reported (~36.9 GiB) | Same source; distinct from total VM disk |
| GPU | None | KVM@TACC educational deployment |
| Network | Floating IP; security groups allow TCP 22, 80, 443 | Operational requirement for SSH and Ingress |

**Utilization (requests vs. allocatable):** Cluster-wide **CPU requests** 1550 m (~9% of 16 cores); **memory requests** 2572 Mi (~8% of allocatable memory). **Observed** usage under light load (`kubectl top node`): ~489 m CPU, ~6.1 GiB memory, indicating substantial headroom relative to requests.

**OpenStack alignment:** Flavor or reservation **vCPU and RAM** from Horizon or `openstack server show` / `openstack flavor show` should agree with the node capacity above. **Disk:** the root (or data) volume must accommodate **80 Gi** in bound **PersistentVolumeClaims** (see §3) plus the operating system, container images, and logs; `local-path` consumes host filesystem space.

---

## 2. Platform services (Kubernetes manifests)

Requests and limits are defined in the repository paths indicated.

| Service | Namespace | CPU request | CPU limit | Memory request | Memory limit | PVC | Source |
|---------|-----------|-------------|-----------|----------------|--------------|-----|--------|
| MLflow | `ml-platform` | 250 m | 1 | 512 Mi | 2 Gi | 20 Gi (`mlflow-data`) | `k8s/platform/mlflow/` |
| MinIO | `ml-platform` | 250 m | 1 | 512 Mi | 2 Gi | 20 Gi (`minio-data`) | `k8s/platform/minio/` |
| Prometheus | `monitoring` | 200 m | 1 | 512 Mi | 2 Gi | 10 Gi (`prometheus-data`) | `k8s/platform/observability/` |
| Grafana | `monitoring` | 100 m | 500 m | 256 Mi | 1 Gi | 5 Gi (`grafana-data`) | `k8s/platform/observability/` |

**Rationale:** Requests are set conservatively for co-location on a single-node cluster; limits bound peak consumption. MLflow and MinIO receive symmetric CPU and memory envelopes. Prometheus receives a higher ceiling for time-series retention and scraping; Grafana remains smaller (UI and metadata).

**Measurement:** Declared values were verified against the node’s pod list (`kubectl describe node`). **Idle** samples from `kubectl top` fell well below limits for these workloads, consistent with limits functioning as upper bounds rather than steady-state demand.

---

## 3. Primary application: Zulip (Helm)

Zulip is deployed with the **docker-zulip** Helm chart. **PostgreSQL** volume size is set in `k8s/zulip/values-chameleon.yaml`; optional `resources` overrides for the main Zulip container remain **commented**. Resource fields for the table below reflect **`kubectl describe node`** on the running release (`zulip-proj15`).

| Component | CPU request | CPU limit | Memory request | Memory limit | Persistent storage |
|-----------|-------------|-----------|----------------|--------------|--------------------|
| Zulip application | — | — | — | — | 10 Gi (`zulip-proj15-data`, `local-path`) |
| PostgreSQL | 100 m | 150 m | 128 Mi | 192 Mi | 15 Gi (`data-zulip-proj15-postgresql-0`, `local-path`) |
| Redis | 100 m | 150 m | 128 Mi | 192 Mi | None (ephemeral) |
| RabbitMQ | 250 m | 380 m | 256 Mi | 384 Mi | None (ephemeral) |
| Memcached | 100 m | 150 m | 128 Mi | 192 Mi | None (ephemeral) |

**Observation:** The main Zulip pod reported **no** requests or limits (**BestEffort** QoS class) but **~196 m CPU** and **~4.2 GiB RAM** in `kubectl top` under the measured workload. Production deployments would set requests and limits (e.g. via the commented blocks in `values-chameleon.yaml`) informed by sustained load.

---

## 4. Persistent volumes and evidence summary

**Bound claims (80 Gi total):**

| Namespace | PersistentVolumeClaim | Capacity | StorageClass |
|-----------|----------------------|----------|--------------|
| `ml-platform` | `mlflow-data` | 20 Gi | `local-path` |
| `ml-platform` | `minio-data` | 20 Gi | `local-path` |
| `monitoring` | `prometheus-data` | 10 Gi | `local-path` |
| `monitoring` | `grafana-data` | 5 Gi | `local-path` |
| `zulip` | `data-zulip-proj15-postgresql-0` | 15 Gi | `local-path` |
| `zulip` | `zulip-proj15-data` | 10 Gi | `local-path` |

**Commands used to reproduce:** `kubectl describe node`; `kubectl top node`; `kubectl top pods -A`; `kubectl get pvc -n <namespace>` for `ml-platform`, `monitoring`, and `zulip`. **Chameleon evidence** (flavor name, vCPU, RAM, root disk) should be attached from Horizon or the OpenStack CLI for the same instance.

**Persistence mapping:** MLflow state and artifacts, MinIO object data, Prometheus TSDB, Grafana data, Zulip PostgreSQL, and Zulip application data each use **ReadWriteOnce** volumes on **`local-path`**, so state survives pod restart. Redis, RabbitMQ, and Memcached in this configuration rely on **ephemeral** storage for their process data.

**Secrets:** Credentials and keys (`terraform.tfvars`, `inventory.ini`, `values-secret.yaml`, TLS material) are excluded from version control per `SECURITY.md` and `.gitignore`.

---

## 5. System components (k3s)

CoreDNS and **metrics-server** expose small **requests** (100 m CPU, 70 Mi memory per component where set). **Traefik** (default Ingress) and **local-path-provisioner** did not declare requests or limits in the captured configuration. These components are bundled with k3s and are ancillary to the workload tables above.
