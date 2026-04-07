# Data role workloads (`ml-data`)

These files are the **Kubernetes equivalents** of each data teammate container from [**docker-compose.yml**](https://github.com/Hard-Hustler/Zulip_Chat_Feature/blob/main/docker-compose.yml) ([Hard-Hustler/Zulip_Chat_Feature](https://github.com/Hard-Hustler/Zulip_Chat_Feature)) — suitable for the “manifest per container” / platform-support deliverable. **You do not need to run them on the cluster yet**; integration (images in a registry, secrets, bucket, `kubectl apply`) can wait until the team is ready.

**MinIO** from compose is **not** recreated here — the manifests assume platform MinIO in `ml-platform`.

## Images (when you integrate later)

Placeholder image names in the YAML point at example tags. Before any real deploy, build from the linked Dockerfiles and push (or retag) as your team agrees:

| Compose service | Dockerfile | Suggested tag (example) |
|-----------------|------------|-------------------------|
| `ingest` | [`data/ingest/Dockerfile`](https://github.com/Hard-Hustler/Zulip_Chat_Feature/blob/main/data/ingest/Dockerfile) | `ghcr.io/<org>/zulip-chat-data-ingest:latest` |
| `online` | [`data/online/Dockerfile`](https://github.com/Hard-Hustler/Zulip_Chat_Feature/blob/main/data/online/Dockerfile) | `ghcr.io/<org>/zulip-chat-data-online:latest` |
| `generator` | [`data/generator/Dockerfile`](https://github.com/Hard-Hustler/Zulip_Chat_Feature/blob/main/data/generator/Dockerfile) | `ghcr.io/<org>/zulip-chat-data-generator:latest` |
| `batch` | [`data/batch/Dockerfile`](https://github.com/Hard-Hustler/Zulip_Chat_Feature/blob/main/data/batch/Dockerfile) | `ghcr.io/<org>/zulip-chat-data-batch:latest` |

Manifests default to `ghcr.io/proj15/...` tags — edit YAML or use `kustomize edit set image` before apply.

## MinIO Secret in `ml-data` (only when deploying)

Pods in `ml-data` cannot read `Secret` objects in `ml-platform`. When you actually apply these manifests, copy the platform secret once (same keys `root-user` / `root-password` as `deploy_platform.yml`):

```bash
kubectl get secret minio-root -n ml-platform -o yaml \
  | sed -e '/^  uid:/d' -e '/^  resourceVersion:/d' -e '/^  creationTimestamp:/d' \
  | sed 's/namespace: ml-platform/namespace: ml-data/' \
  | kubectl apply -f -
```

Or create `minio-root` manually in `ml-data` with the same literals.

## Bucket

Compose uses **`MINIO_BUCKET=zulip-rewriter`**. Ensure that bucket exists on platform MinIO (e.g. MinIO console or `mc mb`).

## Apply order (when deploying)

1. **`data-online`** (Deployment + Service) must be running before **`data-generator`** (it calls `/rewrite`).
2. **`data-ingest`** and **`data-batch`** are Jobs — re-`apply` after a run may require deleting the old Job first:  
   `kubectl delete job -n ml-data data-ingest data-batch --ignore-not-found`

```bash
kubectl apply -f k8s/base/namespaces.yaml
# copy minio secret (see above)
kubectl apply -k k8s/data/
```

## Compose ↔ Kubernetes

| Compose service | Kubernetes | Notes |
|-----------------|------------|--------|
| `minio` | *(platform)* | `minio.ml-platform.svc.cluster.local:9000` |
| `ingest` | Job `data-ingest` | One-shot; same env as compose |
| `online` | Deployment + Service `data-online` | Cluster DNS replaces `online:8000` |
| `generator` | Deployment `data-generator` | `REWRITE_URL` → `http://data-online.ml-data.svc.cluster.local:8000/rewrite` |
| `batch` | Job `data-batch` | Compose `profiles: batch` → apply when needed |
