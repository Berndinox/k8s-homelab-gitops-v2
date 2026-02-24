# SOUL.md — k8s-homelab-gitops-v2

> Persistente Wissensbasis. Vor jedem Task lesen.

---

## Projekt

Kubernetes-Homelab auf 3x Lenovo M920x. Talos Linux, GitOps via ArgoCD.

## Hardware

| Node     | MGMT-IP     | Cluster-IP   | OS-NVMe | Daten-NVMe |
|----------|-------------|--------------|---------|------------|
| m920x-01 | 10.0.200.11 | 10.0.100.11  | ≤500GB  | 2TB        |
| m920x-02 | 10.0.200.12 | 10.0.100.12  | ≤500GB  | 2TB        |
| m920x-03 | 10.0.200.13 | 10.0.100.13  | ≤500GB  | 2TB        |

VIP (kube-apiserver): `10.0.100.10`

## Netzwerk

| Interface          | Typ      | Rolle                         |
|--------------------|----------|-------------------------------|
| enp1s0 + enp1s0d1  | 10G LACP | bond0 → Trunk alle VLANs     |
| eno1               | 1G       | MGMT (VLAN 200, Access Port)  |

| VLAN | Subnetz       | Relevanz                         |
|------|---------------|----------------------------------|
| 10   | 10.0.5.0/24   | DMZ — Cilium LB-Pool             |
| 50   | 10.0.50.0/24  | Server — Cilium LB-Pool, AdGuard |
| 100  | 10.0.100.0/24 | Kubernetes Cluster               |
| 200  | 10.0.200.0/24 | MGMT (eno1)                      |

## Software-Stack

| Komponente   | Version     |
|--------------|-------------|
| Talos Linux  | v1.12.4     |
| Kubernetes   | v1.35.0     |
| Cilium       | v1.17.2     |
| Longhorn     | v1.8.1      |
| KubeVirt     | v1.4.0      |
| CDI          | v1.61.0     |
| ArgoCD       | chart 7.8.3 |
| cert-manager | v1.17.1     |

## Repo-Struktur

```text
cluster/              Talos-Config + alle Bootstrap-Befehle
  talconfig.yaml
  schematic.yaml
  patches/
  COMMANDS.md         Schritt-für-Schritt, pro Host möglich
kubernetes/           ArgoCD App-of-Apps + Manifeste
docs/
  vyos-bgp-config.md  VyOS BGP + uRPF Konfiguration
```

## Entscheidungen

- **Interfaces**: enp1s0 + enp1s0d1 → bond0 (LACP), eno1 (MGMT)
- **Talos Extensions**: iscsi-tools + util-linux-tools (nur für Longhorn)
- **Cilium**: native routing, hybrid LB, eBPF kube-proxy, KubePrism (localhost:7445)
- **Cilium BGP**: nur LB-IPs announcen; Router VyOS (uRPF: loose)
- **LB-Pools**: VLAN 50 Server (10.0.50.x/TBD) + VLAN 10 DMZ (10.0.5.x/TBD)
- **IPv6**: deaktiviert
- **Longhorn**: /var/mnt/longhorn, 3 Replicas, 2TB NVMe je Node
- **DNS**: AdGuard Home — 10.0.50.4 + 10.0.50.5
- **Secrets**: SOPS + Age
- **Domain**: *.local.Klaus.onl
- **GitHub**: github.com/Berndinox/k8s-homelab-gitops-v2

## Offen / TBD

- BGP ASNs: Node-ASN + VyOS-ASN noch nicht festgelegt
- BGP Peer-IP: VyOS auf VLAN 100 (vermutlich 10.0.100.1)
- LB-Pool IP-Ranges: genaue Ranges in VLAN 50 + VLAN 10
- 2TB NVMe Disk-IDs: per Node via `talosctl disks` ermitteln
- Schematic-ID: via factory.talos.dev generieren → in talconfig.yaml eintragen

## Agent-Protokoll

| Datum      | Aktion                                         |
|------------|------------------------------------------------|
| 2026-02-22 | Initialdokumentation, alle Configs erstellt    |
| 2026-02-23 | Vereinfacht: cluster/, COMMANDS.md, Repo clean |
