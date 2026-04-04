# Container inventory (4-person team — joint deliverable)

Each row is one runnable container image. Training, serving, and data owners fill Dockerfile/Compose links; DevOps adds the equivalent Kubernetes manifest used on Chameleon.

| Role | Container / workload name | Purpose | Dockerfile or Compose | Kubernetes manifest (path in repo) | Current status |
|------|---------------------------|---------|------------------------|-------------------------------------|----------------|
| Platform | `mlflow-tracking` | Shared experiment tracking | Bitnami MLflow image in manifest | `k8s/platform/mlflow/` (+ `ingress.yaml`, TLS secret `chameleon-nip-tls`) | Deployed; PVC bound; **HTTPS** via k3s **Traefik** Ingress (`mlflow.<fip>.nip.io`) |
| Platform | `zulip-server` + subcharts (`postgresql`, `redis`, `rabbitmq`, `memcached`) | Base open-source product | App source: [zulip/zulip](https://github.com/zulip/zulip); deployment/chart: [docker-zulip](https://github.com/zulip/docker-zulip) | `k8s/zulip/values-chameleon.yaml`, `k8s/zulip/values-secret.yaml.example`, Ansible `infra/ansible/playbooks/deploy_zulip.yml` | Deployed; **ClusterIP** + **Ingress**; **HTTPS** (`zulip.<fip>.nip.io`); org creation verified |
| Training | _TBD — e.g. `tone-train`_ | Training job image | _link when added_ | _link when added_ | Pending |
| Serving | _TBD — e.g. `tone-serving`_ | Inference API | _link when added_ | _link when added_ | Pending |
| Data | _TBD — e.g. `data-batch`_ | ETL / batch features | _link when added_ | _link when added_ | Pending |

Notes:

- Add one row per distinct image (if training uses a sidecar, add a row for it).
- If a role uses **Docker Compose** for local dev, link `docker-compose.yml` and still provide a **K8s** manifest path for Chameleon (Job, Deployment, or Helm values overlay).
- For grading/demo evidence, keep this table aligned with `Docs/initial-implementation/devops/FLOW_start_to_current.md` and `Docs/initial-implementation/devops/COMMANDS_history_and_explanations.md`.
