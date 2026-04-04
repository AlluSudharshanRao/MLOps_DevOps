# Zulip on Kubernetes (base open-source service)

**Upstream product (source code):** [github.com/zulip/zulip](https://github.com/zulip/zulip) — the Zulip server and web app (Python/Django, etc.). That is the main open-source repo for the platform your ML feature complements.

**How we run it in Kubernetes:** images and the official **Helm chart** come from [docker-zulip](https://github.com/zulip/docker-zulip) (`helm/zulip/`). The chart packages the same server for containerized deployment; day-to-day app behavior and APIs are defined in the `zulip/zulip` tree.

## Prereqs

- Cluster storage class for PostgreSQL / Redis / RabbitMQ PVCs (e.g. k3s `local-path`).
- **Ingress:** k3s default **Traefik**; **`values-chameleon.yaml`** enables Ingress + TLS secret name **`chameleon-nip-tls`** (create the Secret on the cluster — see repo root [`GETTING_STARTED.md`](../../GETTING_STARTED.md), *Step 6 — TLS Secret for Ingress*).
- Hostname aligned with **`SETTING_EXTERNAL_HOST`**: **`zulip.<floating-ip>.nip.io`** (subdomain form so MLflow can use **`mlflow.<same-ip>.nip.io`**).
- Env **`LOADBALANCER_IPS`** (pod CIDR, e.g. `10.42.0.0/16`) so Zulip’s nginx trusts Traefik; optional **`SETTING_OPEN_REALM_CREATION`** for stable **`/new/`**.
- TLS secret and `values-secret.yaml` **not** committed to Git.

## Install (example)

Clone or vendor the chart, then install with team overrides:

```bash
# Example only — adjust paths to where you vendor the chart
helm dependency update ./zulip-chart
helm install zulip-proj99 ./zulip-chart \
  --namespace zulip \
  --create-namespace \
  -f values-chameleon.yaml \
  -f values-secret.yaml
```

`values-secret.yaml` should contain `zulipSecret`, database passwords, etc., and stay **local** or in a secret manager.

## Course demo checklist

1. Pods ready in `zulip` namespace.
2. `kubectl get pods,svc,ingress -n zulip` — Ingress host **`zulip.<fip>.nip.io`**, TLS attached.
3. Browser: **`https://zulip.<fip>.nip.io/`** (accept self-signed warning if applicable); org creation via **`/new/`** or CLI link.

See `values-chameleon.yaml` and `values-secret.yaml.example` for proxy, TLS, and realm-creation flags. End-to-end commands: [`GETTING_STARTED.md`](../../GETTING_STARTED.md).
