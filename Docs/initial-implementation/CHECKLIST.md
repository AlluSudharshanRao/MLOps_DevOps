# Initial implementation checklist (Apr 6)

## Joint (all members)

- [x] Final `contracts/sample_inference_request.json` and `contracts/sample_model_output.json` agreed and representative.
- [ ] `Docs/initial-implementation/containers-matrix.md` complete with real links for every container (Platform completed; Training/Serving/Data pending).

## DevOps / Platform

- [x] Chameleon resources named with `projNN` suffix (`proj15`) and running.
- [x] **IaC:** `infra/terraform/openstack/` applied (VM + FIP + routing path validated).
- [x] **CaC:** Ansible path used (`infra/ansible/`): k3s, platform manifests, Zulip Helm deploy.
- [x] MLflow deployed in `ml-platform` (PVC-backed), pod/service validated.
- [x] Zulip deployed via Helm in `zulip` namespace; pods running; org creation link generated and page reachable.
- [ ] `Docs/initial-implementation/devops/infrastructure-requirements.md` filled with measured CPU/mem/GPU evidence (`kubectl top` capture still pending).
- [ ] Demo videos: (1) Zulip in K8s end-to-end, (2) platform services (e.g. MLflow) in K8s end-to-end.
- [ ] No secrets in Git; disclose LLM-assisted commits per course policy.

## Teammate reminders (for your integration planning)

- **Training:** MLflow on Chameleon, Docker training image, config-driven runs, demo video.
- **Serving:** serving options table, Dockerfile(s), demo on Chameleon.
- **Data:** design doc, object storage bucket, pipelines + demo videos per rubric.
