# Cluster Bootstrap — Befehle

**Voraussetzungen (Windows: Git Bash oder WSL2)**

```powershell
# Windows
winget install kubernetes.kubectl
winget install helm.helm
winget install jqlang.jq
winget install talhelper.talhelper

# talosctl (kein winget-Paket) — PowerShell als Admin:
$version = "v1.12.4"
Invoke-WebRequest `
  -Uri "https://github.com/siderolabs/talos/releases/download/$version/talosctl-windows-amd64.exe" `
  -OutFile "$env:ProgramFiles\talosctl\talosctl.exe"
# Danach einmalig: $env:ProgramFiles\talosctl zum PATH hinzufügen (Systemsteuerung → Umgebungsvariablen)
```

```bash
# macOS
brew install talosctl talhelper helm kubectl jq
```

---

## 0. Schematic-ID + ISO (einmalig)

```bash
cd cluster/

# Schematic-ID generieren und in talconfig.yaml eintragen
curl -sX POST --data-binary @schematic.yaml \
  https://factory.talos.dev/schematics | jq -r .id
# → ID kopieren → talconfig.yaml: talosImageURL ersetzen

# ISO herunterladen (SCHEMATIC_ID durch die obige ID ersetzen)
# https://factory.talos.dev/image/SCHEMATIC_ID/v1.12.4/metal-amd64.iso

# ISO auf USB flashen (Linux/WSL2)
dd if=metal-amd64.iso of=/dev/sdX bs=4M status=progress
```

---

## 1. Disk-IDs ermitteln (vor genconfig)

Jeden Node von USB booten → Talos Maintenance Mode.

```bash
# Pro Node — Disks auslesen
talosctl get discoveredvolumes -n 10.0.200.11 -e 10.0.200.11 --insecure
talosctl get discoveredvolumes -n 10.0.200.12 -e 10.0.200.12 --insecure
talosctl get discoveredvolumes -n 10.0.200.13 -e 10.0.200.13 --insecure
```

Auf allen M920x identisch: nvme0n1 = 2TB (Longhorn-Disk), nvme1n1 = 256GB (System-Disk).

---

## 2. Configs generieren

```bash
cd cluster/

# Einmalig Secrets generieren (NUR wenn talsecret.yaml noch nicht existiert!)
# talsecret.yaml NIEMALS in git committen!
talhelper gensecret > talsecret.yaml

# Configs aus talconfig.yaml + patches/ generieren
talhelper genconfig
# → erzeugt clusterconfig/homelab-m920x-01.yaml, homelab-m920x-02.yaml, homelab-m920x-03.yaml, talosconfig
```

> **Wichtig:** `talsecret.yaml` enthält alle Cluster-Secrets (CA, Certs, Bootstrap-Token).
> Sicher verwahren, Backup anlegen! In `.gitignore` eingetragen.

---

## 2b. Validierung (optional, kein Hardware nötig)

### Schema-Check — prüft Syntax + Struktur der generierten Configs

```bash
# Jeden generierten Config gegen das Talos-Schema validieren
talosctl validate --config clusterconfig/homelab-m920x-01.yaml --mode metal
talosctl validate --config clusterconfig/homelab-m920x-02.yaml --mode metal
talosctl validate --config clusterconfig/homelab-m920x-03.yaml --mode metal
```

Fängt: falsche Feldnamen, ungültige Werte, fehlende Pflichtfelder.
Fängt nicht: falsche NIC-Namen, falsche Disk-IDs (nur auf echter Hardware prüfbar).

---

## 3. Config anwenden

Nodes müssen im Maintenance Mode (von USB gebootet) sein.

> **Wichtig:** In Maintenance Mode haben Nodes NOCH KEINE statische IP!
> Sie bekommen via DHCP eine temporäre IP (z.B. 10.0.200.95).
> Statische IP (10.0.200.11/12/13) gilt erst NACH dem Anwenden der Config.

```bash
# Maintenance-IP ermitteln (pro Node)
nmap -sn 10.0.200.0/24   # Talos-Node taucht als "talos" auf
# oder: talosctl version -e 10.0.200.X -n 10.0.200.X --insecure  (IP ausprobieren)

# Config anwenden — MAINTENANCE_IP = die DHCP-IP des Nodes im Maintenance Mode
talosctl apply-config -n <MAINTENANCE_IP_01> -e <MAINTENANCE_IP_01> --insecure -f clusterconfig/homelab-m920x-01.yaml
talosctl apply-config -n <MAINTENANCE_IP_02> -e <MAINTENANCE_IP_02> --insecure -f clusterconfig/homelab-m920x-02.yaml
talosctl apply-config -n <MAINTENANCE_IP_03> -e <MAINTENANCE_IP_03> --insecure -f clusterconfig/homelab-m920x-03.yaml
```

Nodes laden den Installer (~10-15 Min) und rebooten dann automatisch in die installierte Talos-Instanz.
Nach dem Reboot sind die statischen IPs (10.0.200.11/12/13) aktiv.

---

## 4. Cluster bootstrappen

**Nur einmal ausführen!** Beim zweiten Mal wird etcd beschädigt.

```bash
talosctl --talosconfig clusterconfig/talosconfig \
  -n 10.0.200.11 bootstrap

# Warten bis Cluster healthy (bis zu 5 min)
talosctl --talosconfig clusterconfig/talosconfig \
  -n 10.0.200.11,10.0.200.12,10.0.200.13 health --wait-timeout 5m
```

---

## 5. kubeconfig

```bash
talosctl --talosconfig clusterconfig/talosconfig \
  -n 10.0.200.11 kubeconfig ./kubeconfig

export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes   # alle 3 Nodes: NotReady (noch kein CNI — normal)
```

---

## 6. + 7. Cilium + ArgoCD installieren (Bootstrap-Script)

> **Kurzform:** `bash scripts/bootstrap.sh` — installiert Cilium, ArgoCD und wendet die Root-App an.
> Voraussetzung: `KUBECONFIG` gesetzt (ggf. kubeconfig-mgmt verwenden, siehe Hinweis unten).

```bash
cd cluster/
# MGMT-IP verwenden falls VIP (10.0.100.10) nicht erreichbar vom Bootstrap-Rechner:
sed 's|10.0.100.10|10.0.200.13|g' clusterconfig/kubeconfig > clusterconfig/kubeconfig-mgmt
export KUBECONFIG=$(pwd)/clusterconfig/kubeconfig-mgmt

bash scripts/bootstrap.sh
```

---

## 6. Cilium installieren (manuell / Details)

> **Hinweis M920x:** `loadBalancer.acceleration=native` (XDP) wird vom eno1-Treiber nicht
> unterstützt → auf `disabled` setzen. Cilium läuft trotzdem voll funktional.
> **Hinweis kubeconfig:** API-Server lauscht auf VIP 10.0.100.10 (Cluster-VLAN). Wenn der
> Bootstrap-Rechner nur im MGMT-VLAN ist, kubeconfig auf MGMT-IP umbiegen:
> `sed 's|10.0.100.10|10.0.200.13|g' kubeconfig > kubeconfig-mgmt`

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update cilium

# Capabilities-Syntax kollidiert mit Bash-Brace-Expansion → Values-File verwenden
cat > /tmp/cilium-values.yaml << 'EOF'
ipam:
  mode: kubernetes
kubeProxyReplacement: true
k8sServiceHost: localhost
k8sServicePort: 7445
routingMode: native
autoDirectNodeRoutes: true
ipv4NativeRoutingCIDR: 10.244.0.0/16
enableIPv4Masquerade: true
ipv6:
  enabled: false
bpf:
  masquerade: true
  hostLegacyRouting: false
  tproxy: true
loadBalancer:
  algorithm: maglev
  mode: hybrid
  acceleration: disabled   # M920x eno1/bond: kein nativer XDP-Support
endpointRoutes:
  enabled: true
bandwidthManager:
  enabled: true
  bbr: true
hostFirewall:
  enabled: true
hostPort:
  enabled: true
localRedirectPolicy: true
bgpControlPlane:
  enabled: true
hubble:
  relay:
    enabled: true
  ui:
    enabled: true
operator:
  replicas: 1
cgroup:
  autoMount:
    enabled: false
  hostRoot: /sys/fs/cgroup
securityContext:
  capabilities:
    ciliumAgent:
      - CHOWN
      - KILL
      - NET_ADMIN
      - NET_RAW
      - IPC_LOCK
      - SYS_ADMIN
      - SYS_RESOURCE
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
    cleanCiliumState:
      - NET_ADMIN
      - SYS_ADMIN
      - SYS_RESOURCE
EOF

helm upgrade --install cilium cilium/cilium \
  --version 1.17.2 \
  --namespace kube-system \
  -f /tmp/cilium-values.yaml \
  --wait --timeout 5m

kubectl get nodes   # jetzt Ready

# Single-Node: Control-Plane-Taint entfernen damit alle Pods schedulen können
# (entfällt wenn Nodes 01+02 gejoint sind — dann genug Worker-Kapazität)
kubectl taint nodes m920x-03 node-role.kubernetes.io/control-plane:NoSchedule-
```

---

## 7. ArgoCD installieren

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

kubectl create namespace argocd

helm upgrade --install argocd argo/argo-cd \
  --version 7.8.3 \
  --namespace argocd \
  --set server.insecure=true \
  --set server.service.type=LoadBalancer \
  --set configs.cm."application\.resourceTrackingMethod"=annotation \
  --wait --timeout 5m

# Root App-of-Apps anwenden (GitOps übernimmt ab hier)
kubectl apply -f ../kubernetes/bootstrap/root-app/application.yaml

# Admin-Passwort
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## 8. Longhorn-Disk einrichten (für neue Nodes)

> **Node 03 ist bereits erledigt** — nvme0n1 wurde gewiped, Patch ist in talconfig.yaml aktiv,
> `/var/mnt/longhorn` ist gemountet. Diese Schritte gelten für Nodes 01+02 wenn sie joinen.
> **Wichtig:** nvme0n1 auf M920x hat alte Partitionen (Ubuntu/LVM). Der direkte Wipe
> scheitert wenn dm-0 aktiv ist. Beste Methode: **im Talos Maintenance Mode wischen**
> (vor apply-config), dann hat das LVM noch keine Chance zu aktivieren.

```bash
# Idealer Weg: Wischen im Maintenance Mode (bevor Config angewandt wird)
# Node von USB booten → Maintenance Mode → DHCP-IP ermitteln
talosctl wipe disk nvme0n1 \
  -n <MAINTENANCE_IP> -e <MAINTENANCE_IP> --insecure

# Danach normal Config anwenden (Schritt 3)
# → Talos provisioniert nvme0n1 automatisch als /var/mnt/longhorn (UserVolumeConfig)
```

```bash
# Fallback: Node läuft bereits (LVM blockiert direkten Wipe)
# Privilegierten Pod zum Nullen der LVM-Metadata verwenden:
kubectl label namespace default pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl run nvme-wipe --restart=Never --image=busybox \
  --overrides='{"spec":{"nodeName":"<NODE>","tolerations":[{"operator":"Exists"}],"containers":[{"name":"w","image":"busybox","command":["sh","-c","dd if=/dev/zero of=/dev/nvme0n1p3 bs=4M count=10 && echo DONE"],"securityContext":{"privileged":true},"volumeMounts":[{"name":"dev","mountPath":"/dev"}]}],"volumes":[{"name":"dev","hostPath":{"path":"/dev"}}]}}'
kubectl logs nvme-wipe   # DONE abwarten
kubectl delete pod nvme-wipe

# Node rebooten (dm-0 aus Kernel flushen)
talosctl reboot -n <NODE_IP> -e <NODE_IP> --talosconfig clusterconfig/talosconfig

# Nach Reboot: sauberer Wipe
talosctl wipe disk nvme0n1 \
  -n <NODE_IP> -e <NODE_IP> --talosconfig clusterconfig/talosconfig

# Config anwenden → Talos mountet nvme0n1 als /var/mnt/longhorn
talosctl apply-config -n <NODE_IP> -e <NODE_IP> \
  --talosconfig clusterconfig/talosconfig -f clusterconfig/homelab-m920x-0X.yaml
```

```bash
# Prüfen ob Volume ready
talosctl get volumestatus -n <NODE_IP> -e <NODE_IP> \
  --talosconfig clusterconfig/talosconfig | grep longhorn
# Erwartet: u-longhorn   partition   ready   /dev/nvme0n1p1   2.0 TB
```

---

## Debug / Troubleshooting

```bash
# Node-Status
talosctl --talosconfig clusterconfig/talosconfig \
  -n 10.0.200.11,10.0.200.12,10.0.200.13 health

# Logs eines Nodes
talosctl --talosconfig clusterconfig/talosconfig \
  -n 10.0.200.11 logs kubelet

# Einzelnen Node reset (komplett neu aufsetzen)
talosctl --talosconfig clusterconfig/talosconfig \
  -n 10.0.200.12 reset --graceful=false --reboot
# danach: Schritt 3 für diesen Node wiederholen

# Cilium-Status
kubectl -n kube-system exec -it ds/cilium -- cilium status

# ArgoCD Apps
kubectl -n argocd get applications
```
