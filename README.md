# MLOps Project - Zulip on Chameleon (Solo DevOps Repo)

This repository tracks my DevOps/platform work for the MLOps course project: provisioning and operating a self-hosted Zulip + platform services stack on Chameleon Cloud using Infrastructure as Code and Configuration as Code.

## Project objective

Build a reproducible deployment pipeline from cloud resources to running Kubernetes workloads:

- Provision OpenStack infrastructure on Chameleon (`KVM@TACC`) with Terraform.
- Configure and operate Kubernetes (k3s) with Ansible.
- Deploy platform service (MLflow) and application service (Zulip via Helm).
- Document the full engineering flow, issues, fixes, and operational evidence.

## Current implementation status

- OpenStack VM + networking + floating IP provisioned and reachable.
- k3s installed and verified.
- MLflow deployed with persistent volume in Kubernetes.
- Zulip deployed from `docker-zulip/helm/zulip`; pods running and org-creation flow verified.
- Detailed docs updated under `Docs/initial-implementation/devops/`.

## Repository structure

- `Docs/`
  - Primary project documentation, including end-to-end flow, command history, explanations, and requirements.
- `infra/`
  - `terraform/openstack/`: Chameleon infrastructure provisioning (VM/network/FIP).
  - `terraform/k8s-apps/`: optional Terraform-managed k8s app path.
  - `ansible/`: k3s install and app deployment playbooks.
- `k8s/`
  - Kubernetes manifests and Helm value overlays (MLflow + Zulip).
- `contracts/`
  - Sample request/response artifacts used by project milestones.
- `zulip/`
  - Upstream Zulip source checkout used for product/context reference.

## How this repo is used

1. Provision cloud resources via Terraform.
2. Configure cluster and apply platform workloads via Ansible.
3. Deploy Zulip with Helm values tuned for Chameleon/k3s.
4. Validate runtime with `kubectl` and capture evidence for milestone deliverables.

## Notes

- This is a personal working repository for my DevOps track deliverables.
- Secrets are not committed (`values-secret.yaml`, credentials, private keys are excluded via `.gitignore`).
