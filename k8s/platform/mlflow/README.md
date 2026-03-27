# MLflow (shared platform service)

Apply after namespaces exist:

```bash
kubectl apply -f ../base/namespaces.yaml
kubectl apply -k .
```

Expose for course staff (pick one):

- **Port-forward:** `kubectl -n ml-platform port-forward svc/mlflow 5000:5000`
- **NodePort / LoadBalancer / Ingress:** add a manifest; keep TLS and secrets out of Git (use SealedSecrets or external secret store if required).

For production-style tracking, point `default-artifact-root` at object storage (S3-compatible on Chameleon) instead of the PVC; this minimal stack satisfies “persistent across pod restarts” for the initial milestone.
