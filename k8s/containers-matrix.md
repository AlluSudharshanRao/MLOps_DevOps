# Container inventory (team + platform)

Each row is one **runnable container image** (or one Helm/chart bundle where noted). Training, serving, and data owners maintain Dockerfile / Compose links; DevOps provides the **Kubernetes manifest** path used on Chameleon (apply after `k8s/base/namespaces.yaml`).

| Role | Container / workload | Purpose | Dockerfile or Compose | Kubernetes manifest (this repo) | Notes |
|------|----------------------|---------|------------------------|-----------------------------------|--------|
| **Platform** | `mlflow` (custom Deployment) | Experiment tracking UI + API | Image + args in manifest ([upstream](https://github.com/mlflow/mlflow)) | [`platform/mlflow/`](platform/mlflow/) | Primary path; optional Bitnami via [`../infra/terraform/k8s-apps/`](../infra/terraform/k8s-apps/) |
| **Platform** | MinIO (`minio/minio`) | S3-compatible object store | [MinIO image](https://hub.docker.com/r/minio/minio) | [`platform/minio/`](platform/minio/) | Credentials: `minio-root` Secret (Ansible) |
| **Platform** | Prometheus + Grafana | Metrics + dashboards | Images in manifests | [`platform/observability/`](platform/observability/) | |
| **Platform** | Zulip + PostgreSQL, Redis, RabbitMQ, Memcached | Team chat product | App: [zulip/zulip](https://github.com/zulip/zulip); chart: [docker-zulip](https://github.com/zulip/docker-zulip) | [`zulip/values-chameleon.yaml`](zulip/values-chameleon.yaml), [`zulip/values-secret.yaml.example`](zulip/values-secret.yaml.example), deploy [`../infra/ansible/playbooks/deploy_zulip.yml`](../infra/ansible/playbooks/deploy_zulip.yml) | |
| **Serving** | `tone-classifier` (PyTorch / ONNX / quantized) | Classifier API | [Dockerfile](https://github.com/rithwik0908/mlops-serving/blob/main/serving/classifier/Dockerfile) | [`inference/classifier-pytorch-deployment.yaml`](inference/classifier-pytorch-deployment.yaml), [`inference/classifier-onnx-deployment.yaml`](inference/classifier-onnx-deployment.yaml), [`inference/classifier-quantized-deployment.yaml`](inference/classifier-quantized-deployment.yaml) | Same image; `SERVING_BACKEND` selects backend |
| **Serving** | `tone-generator` | LLM rewrite API | [Dockerfile](https://github.com/rithwik0908/mlops-serving/blob/main/serving/generator/Dockerfile) | [`inference/generator-deployment.yaml`](inference/generator-deployment.yaml) | |
| **Training** | `classifier-training` | Fine-tune classifier | Teammate repo (Dockerfile path in Job comments) | [`training/classifier-training-job.yaml`](training/classifier-training-job.yaml) | Image: `ghcr.io/proj15/classifier-training:latest` — align tag with your registry |
| **Training** | `generator-training` | Fine-tune generator | Teammate repo | [`training/generator-training-job.yaml`](training/generator-training-job.yaml) | Image: `ghcr.io/proj15/generator-training:latest` |
| **Data** | `data-pipeline` | ETL → MinIO | Teammate repo | [`data/data-pipeline-job.yaml`](data/data-pipeline-job.yaml) | Image: `ghcr.io/proj15/data-pipeline:latest` |
| **Platform (optional)** | Sealed Secrets controller | Git-safe encrypted secrets | [Upstream image](https://github.com/bitnami-labs/sealed-secrets) | [`addons/sealed-secrets/`](addons/sealed-secrets/) | Extra-credit / bonus path |

**Apply bundles**

- All inference Deployments: `kubectl apply -k k8s/inference/`
- Namespaces: `kubectl apply -f k8s/base/namespaces.yaml`

**Maintenance:** Replace placeholder `ghcr.io/proj15/...` image names with your team’s registry paths when images are published; add permanent Dockerfile links in the table for training/data rows when repos are final.
