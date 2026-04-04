# Infrastructure requirements table (DevOps — Apr 6)

This file now reflects current deployment status. Keep updating it with measured right-sizing evidence as you run tests.

| Workload (K8s object) | Namespace | CPU request | CPU limit | Memory request | Memory limit | GPU | Notes / evidence (Chameleon) |
|------------------------|-----------|-------------|-----------|----------------|--------------|-----|------------------------------|
| `mlflow` Deployment | `ml-platform` | 250m | 1 | 512Mi | 2Gi | — | Deployed and previously validated; capture fresh `kubectl top` screenshot/date before submission |
| Zulip chart — postgresql | `zulip` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | — | Deployed via chart defaults + `values-chameleon.yaml`; fill with `kubectl top` evidence |
| Zulip chart — redis | `zulip` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | — | Deployed and running; measure under representative load |
| Zulip chart — rabbitmq | `zulip` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | — | Deployed and running; measure under representative load |
| Zulip chart — memcached | `zulip` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | — | Deployed and running; include observed peak |
| Zulip chart — zulip | `zulip` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | — | Pod reached `1/1 Running`; org-link flow works; fill measured steady-state and startup peaks |
| Serving — classifier | `ml-serving` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | — | Pending teammate deployment |
| Serving — generator | `ml-serving` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | 1× _type_ | Pending teammate deployment |

## Current validated deployment status

- OpenStack VM + floating IP provisioned by Terraform and reachable by SSH.
- k3s installed via Ansible (bundled **Traefik** serves **Ingress** on **80/443**).
- MLflow in `ml-platform`: Deployment, PVC, Service, **Ingress** (`mlflow.<fip>.nip.io`), TLS Secret `chameleon-nip-tls`.
- Zulip Helm release `zulip-proj15` in `zulip`: ClusterIP + **Ingress** (`zulip.<fip>.nip.io`), same TLS secret name; `LOADBALANCER_IPS` / proxy settings for Traefik documented in `values-chameleon.yaml`.
- Security group: **TCP 22, 80, 443** toward the floating IP (443 required for browser HTTPS).
- Zulip: organization creation verified in browser (stable **`/new/`** path enabled for demos + optional CLI single-use links).

## Evidence commands to run and paste into notes

```bash
kubectl get pods -A -o wide
kubectl get ingress -A
kubectl top pod -A
kubectl top node
kubectl get svc -n ml-platform
kubectl get svc -n zulip
```

For each row above, record:
- timestamp,
- output snippet/screenshot,
- load condition (idle / demo traffic / stress run),
- chosen request/limit and rationale.

## Freshness / automation (proposal alignment)

- **Retrain cadence:** weekly baseline; on-demand when acceptance rate or drift thresholds trip (document exact gates in CI).
- **Where it runs:** describe which manifests or pipelines apply new model versions (serving Deployment image tag, canary Service weights, etc.).

## Scaling assumptions (from team proposal — validate on Chameleon)

- Typical ~5 req/s, peak ~20 req/s for the tone feature; Zulip baseline load separate.
- Autoscaling: e.g. HPA on classifier CPU > 70% once metrics server is available.
