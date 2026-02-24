# k8s-homelab-gitops-v2

GitOps-getriebenes Kubernetes Homelab auf 3x Lenovo M920x.

## Stack

| Komponente   | Aufgabe                        |
|--------------|--------------------------------|
| Talos Linux  | Immutable OS, API-driven       |
| Cilium       | CNI, BGP, LoadBalancer, Hubble |
| Longhorn     | Distributed Block Storage      |
| KubeVirt     | VM-Workloads auf Kubernetes    |
| Multus       | Multi-NIC / VLAN-Zugriff       |
| ArgoCD       | GitOps / Apps-of-Apps          |
| cert-manager | TLS-Zertifikate                |

## Cluster

- **3x Lenovo M920x** — alle Control Plane + Worker
- **Talos v1.12.4** / **Kubernetes v1.35.0**
- **API Endpoint:** `https://10.0.100.10:6443` (VIP)
- **Interne Domain:** `*.local.Klaus.onl`

## Bootstrap

Alle Befehle und Schritte: [cluster/COMMANDS.md](cluster/COMMANDS.md)

```text
1. Schematic-ID via factory.talos.dev → in cluster/talconfig.yaml eintragen
2. 2TB NVMe Disk-ID ermitteln → in cluster/patches/common.yaml eintragen
3. talhelper genconfig
4. talosctl apply-config  (pro Host möglich)
5. talosctl bootstrap
6. helm install cilium
7. helm install argocd → ArgoCD übernimmt alles weitere
```

## Repo-Struktur

```text
cluster/     Talos-Config + Bootstrap-Befehle
kubernetes/  ArgoCD Manifeste (Apps-of-Apps)
docs/        VyOS BGP-Konfiguration
```
