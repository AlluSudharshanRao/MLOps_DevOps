# Zulip on Kubernetes (base open-source service)

**Upstream product (source code):** [github.com/zulip/zulip](https://github.com/zulip/zulip) — the Zulip server and web app (Python/Django, etc.). That is the main open-source repo for the platform your ML feature complements.

**How we run it in Kubernetes:** images and the official **Helm chart** come from [docker-zulip](https://github.com/zulip/docker-zulip) (`kubernetes/chart/zulip/`). The chart packages the same server for containerized deployment; day-to-day app behavior and APIs are defined in the `zulip/zulip` tree.

## Prereqs

- Cluster storage class for PostgreSQL / Redis / RabbitMQ PVCs.
- A hostname (DNS or `/etc/hosts`) and TLS secret **not** stored in this repo.
- Sufficient worker memory; start from chart defaults and tighten using `kubectl top` + the infrastructure table.

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
2. `kubectl get pods,svc,ingress -n zulip`
3. Browser: load login page and complete a minimal smoke test.

See `values-chameleon.yaml` for sizing placeholders and ingress class hints.
