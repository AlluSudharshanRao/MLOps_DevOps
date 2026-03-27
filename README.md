# MLOps course project — Zulip Multi-Tone Assistant

Monorepo for a four-person team: training, serving, data, and platform (DevOps). Base chat product: [Zulip server](https://github.com/zulip/zulip) (self-hosted on Chameleon via Kubernetes; see `k8s/zulip/`).

- **Joint contracts:** `contracts/` (input/output JSON samples for Apr 6).
- **Initial implementation docs:** `docs/initial-implementation/`.
- **IaC / CaC (Terraform):** `infra/terraform/openstack/` (Chameleon) and `infra/terraform/k8s-apps/` (cluster).
- **Kubernetes:** `k8s/` (namespaces, platform services, Zulip Helm values).

All runnable systems and demos target **Chameleon Cloud** (resource names must include your `projNN` suffix).
