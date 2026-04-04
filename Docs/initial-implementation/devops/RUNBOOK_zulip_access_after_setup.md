# Zulip on Chameleon: keeps running? Re-access from your PC

This note assumes **k3s** on the VM, the default **Traefik** ingress controller, Zulip Helm release **`zulip-proj15`** in namespace **`zulip`**, **ClusterIP** Zulip Service, **Ingress** on **`zulip.<floating-ip>.nip.io`**, and **TLS** on **TCP 443** via Kubernetes Secret **`chameleon-nip-tls`** (self-signed is fine for class demos).

Full bring-up from zero is still in `RUNBOOK_chameleon_k8s_zulip.md` and `COMMANDS_history_and_explanations.md`.

**Legacy path:** If you still use **NodePort + VM nginx on 8080**, see git history of this file or `FLOW_start_to_current.md` §8.

---

## Will it keep running?

| Piece | Typical behavior |
|--------|------------------|
| **k3s** | systemd service `k3s` — survives reboot if enabled (default with Ansible install). |
| **Traefik** | Deployed by k3s; serves Ingress objects across reboots. |
| **Pods (Zulip, Postgres, …)** | Kubernetes restarts them after a node reboot; data stays on PVCs if storage is intact. |
| **Helm release** | Stored in the cluster; no need to reinstall after reboot unless you delete the release or cluster. |
| **Floating IP** | Stays until you disassociate it or delete the instance. |
| **OpenStack security group** | Allow **TCP 22** (SSH), **TCP 80** (HTTP → ACME redirects / Traefik), and **TCP 443** (HTTPS). |

**It stops or breaks if:** you delete or rebuild the VM, remove volumes, uninstall k3s/Helm, change/clear `values-secret.yaml` without a backup, or remove SG rules.

---

## HTTPS (TLS at Ingress) — one-time setup on the VM

Complexity is low: one self-signed certificate covering **both** hostnames, two `kubectl create secret` commands, then Helm/`kubectl apply` as usual. Browsers will show “not trusted” until you click through — that is expected for self-signed certs.

1. Generate cert + key (replace IPs/hostnames if your floating IP changed):

```bash
cd /tmp
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=zulip.129.114.26.117.nip.io" \
  -addext "subjectAltName=DNS:zulip.129.114.26.117.nip.io,DNS:mlflow.129.114.26.117.nip.io"
```

If `-addext` fails (old OpenSSL), use a minimal `openssl.cnf` with `subjectAltName` instead.

2. Create the same secret name in **both** namespaces (Ingress manifests expect **`chameleon-nip-tls`**):

```bash
kubectl create secret tls chameleon-nip-tls -n zulip --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls chameleon-nip-tls -n ml-platform --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -
```

3. Apply / upgrade workloads (`values-chameleon.yaml` and `k8s/platform/mlflow/ingress.yaml` already reference this secret).

4. **`~/values-secret.yaml`:** use **`SETTING_EXTERNAL_HOST: "zulip.129.114.26.117.nip.io"`** (hostname only, no `:443`). Do **not** duplicate **`ZULIP_CUSTOM_SETTINGS`** here if it would override `values-chameleon.yaml`; that file already sets **`USE_X_FORWARDED_HOST`** and **`SECURE_PROXY_SSL_HEADER`** for HTTPS behind Traefik.

**More work, trusted certs:** install **cert-manager** + **Let’s Encrypt** ClusterIssuer (HTTP-01 needs port **80** reachable on the public IP). Fine for production-shaped demos; not required for the course if a self-signed Ingress TLS is acceptable.

---

## How to open Zulip from your laptop (normal case)

`https://zulip.129.114.26.117.nip.io/`

Replace the IP in the hostname if needed. Accept the **self-signed** warning once.

**MLflow:** `https://mlflow.129.114.26.117.nip.io/`

Security group: **TCP 443** (and **80** if you rely on HTTP→HTTPS or ACME).

---

## After a VM reboot — quick health check (SSH to VM)

```bash
sudo systemctl status k3s --no-pager
export KUBECONFIG=$HOME/.kube/config
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
kubectl get ingress -A
kubectl get pods -n zulip
curl -skI -H "Host: zulip.129.114.26.117.nip.io" https://127.0.0.1/
```

Expect: **k3s** active; **Traefik** pod running; **Ingress** rows for `zulip` (and `ml-platform` for MLflow); Zulip pods **Running**; curl returns HTTP headers from Traefik.

---

## If the website does not load from your PC

1. **Port 443:** `Test-NetConnection -ComputerName <FLOATING_IP> -Port 443` — should succeed.
2. **TLS secret:** `kubectl get secret chameleon-nip-tls -n zulip` and `-n ml-platform` — must exist.
3. **Ingress:** `kubectl describe ingress -n zulip` — TLS section and backends should be **Ready**.
4. **Host match:** `SETTING_EXTERNAL_HOST` must equal the **Ingress** host (no `:443` in the hostname).
5. **On VM:** `sudo ss -tlnp | grep ':443 '` — Traefik (or svclb) should listen on **443**.

---

## Optional: access only via SSH (no public 80)

Port-forward Traefik’s HTTP port (or the Traefik service NodePort if you use that mode):

```text
ssh -N -L 8080:127.0.0.1:80 cc@<FLOATING_IP>
```

Then open `http://zulip.129.114.26.117.nip.io:8080/` only if you map that hostname to `127.0.0.1` in `hosts` **and** your forwarded local port matches what you put in the URL — simpler is to use `curl -H "Host: zulip...." http://127.0.0.1:8080` on the laptop while the tunnel is up.

---

## Helm / Zulip settings to keep aligned

- **`SETTING_EXTERNAL_HOST`** must match the **Ingress** `host` (e.g. `zulip.129.114.26.117.nip.io`).
- **`LOADBALANCER_IPS`** (env, e.g. `10.42.0.0/16`) writes **`[loadbalancer] ips`** in **`/etc/zulip/zulip.conf`** for **container nginx** — required so Traefik is trusted (avoids **`ProxyMisconfigurationError`**). Put this in **`~/values-secret.yaml`** if Helm merge drops it from `values-chameleon.yaml`.
- **`SETTING_OPEN_REALM_CREATION: "True"`** enables a **stable** org-creation URL: **`https://<external-host>/new/`** (demo use; anyone who can reach the server can start signup).
- **`ZULIP_CUSTOM_SETTINGS`** in `values-chameleon.yaml` should include **`USE_X_FORWARDED_HOST`**, **`SECURE_PROXY_SSL_HEADER`**, and Django **`LOAD_BALANCER_IPS`** consistent with Traefik. A **partial** `ZULIP_CUSTOM_SETTINGS` in the secret file can **replace** the whole block from chameleon — merge carefully.

Secrets live in **`~/values-secret.yaml`** on the VM (gitignored in the repo). After edits:

```bash
cd ~/docker-zulip/helm/zulip
helm dependency update .
helm upgrade --install zulip-proj15 . \
  --namespace zulip \
  --kubeconfig "$HOME/.kube/config" \
  -f /opt/mlops_project/k8s/zulip/values-chameleon.yaml \
  -f "$HOME/values-secret.yaml"
```

(Adjust chart path and values paths if yours differ.)

---

## New organization link

```bash
kubectl exec -n zulip zulip-proj15-0 -c zulip -- runuser -u zulip -- \
  /home/zulip/deployments/current/manage.py generate_realm_creation_link
```

Open the printed URL in the browser **as given** (it should use the same host as `SETTING_EXTERNAL_HOST`).

---

## Troubleshooting quick reference

| Symptom | Likely cause | Check / fix |
|--------|----------------|-------------|
| Chrome **“Not secure”** on `https://` | Self-signed Ingress cert | Expected; proceed or trust cert / use Let’s Encrypt. |
| Timeout to **:443** | OpenStack SG blocks **443** | Add TCP 443 ingress rule; `Test-NetConnection`. |
| Traefik **404** (black page) | **Host** not on any Ingress rule | Use **`zulip.<ip>.nip.io`**, not bare `<ip>.nip.io`. |
| Zulip **500** `ProxyMisconfigurationError` | Traefik pod IP not in **`loadbalancer ips`** | **`LOADBALANCER_IPS`** env + pod restart; verify **`zulip.conf`**. |
| **`/new/`** “link required” | **`OPEN_REALM_CREATION`** false | **`SETTING_OPEN_REALM_CREATION: "True"`** + **`helm upgrade`**. |
| CLI link wrong host | Pod env stale | **`helm upgrade`** + **`kubectl delete pod`** `zulip-proj15-0`. |
