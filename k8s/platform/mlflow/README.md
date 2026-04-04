# MLflow (shared platform service)

Apply after namespaces exist:

```bash
kubectl apply -f ../base/namespaces.yaml
kubectl apply -k .
```

Expose for course staff:

- **Current (Chameleon):** **Ingress** `ingress.yaml` — **`https://mlflow.<floating-ip>.nip.io`** via k3s **Traefik** and TLS secret **`chameleon-nip-tls`** (same cert as Zulip; create Secret on cluster, not in Git).
- **Local debug:** `kubectl -n ml-platform port-forward svc/mlflow 5000:5000`

For production-style tracking, point `default-artifact-root` at object storage (S3-compatible on Chameleon) instead of the PVC; this minimal stack satisfies “persistent across pod restarts” for the initial milestone.
