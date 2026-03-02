#!/usr/bin/env bash
# bootstrap.sh — Einmalige Cluster-Bootstrap-Schritte (Cilium + Flux)
#
# Voraussetzungen:
#   - talosctl bootstrap bereits ausgeführt (Schritt 4)
#   - kubeconfig vorhanden (Schritt 5)
#   - KUBECONFIG gesetzt
#   - GITHUB_TOKEN gesetzt (Personal Access Token mit repo-Rechten)
#   - flux CLI installiert: https://fluxcd.io/flux/installation/
#
# Hinweis M920x: API-Server lauscht auf VIP 10.0.100.10 (Cluster-VLAN).
# Falls der Bootstrap-Rechner nur im MGMT-VLAN (10.0.200.x) ist:
#   sed 's|10.0.100.10|10.0.200.13|g' clusterconfig/kubeconfig > clusterconfig/kubeconfig-mgmt
#   export KUBECONFIG=$(pwd)/clusterconfig/kubeconfig-mgmt
#
# Ausführen aus dem Repo-Root:
#   export KUBECONFIG=$(pwd)/cluster/clusterconfig/kubeconfig-mgmt
#   export GITHUB_TOKEN=<dein-token>
#   bash cluster/scripts/bootstrap.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== Bootstrap: Cilium + Flux ==="
echo "KUBECONFIG:   ${KUBECONFIG:-nicht gesetzt — bitte setzen!}"
echo "GITHUB_TOKEN: ${GITHUB_TOKEN:+gesetzt}${GITHUB_TOKEN:-nicht gesetzt — bitte setzen!}"
echo ""

# --- Preflight ---
for cmd in kubectl helm flux; do
  command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd nicht gefunden. Bitte installieren."; exit 1; }
done

if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "ERROR: KUBECONFIG ist nicht gesetzt."
  exit 1
fi
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: GITHUB_TOKEN ist nicht gesetzt."
  exit 1
fi

kubectl cluster-info --request-timeout=5s || {
  echo "ERROR: Kein Cluster erreichbar. KUBECONFIG prüfen."
  exit 1
}

# --- Helm Repos ---
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium

# --- Cilium installieren (MTU-Workaround) ---
# helm install/upgrade scheitert ohne laufendes Cilium: das Helm-Release-Secret (>1MB)
# überschreitet die effektive MTU der externen Verbindung zum API-Server.
# helm template | kubectl apply umgeht das — Ressourcen werden einzeln gepusht.
echo "[1/3] Cilium installieren (v1.19.1) — MTU-Workaround via helm template..."

CILIUM_VALUES=$(mktemp /tmp/cilium-values-XXXX.yaml)
trap "rm -f $CILIUM_VALUES" EXIT

cat > "$CILIUM_VALUES" << 'EOF'
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
  acceleration: disabled
endpointRoutes:
  enabled: true
bandwidthManager:
  enabled: true
  bbr: true
hostFirewall:
  enabled: false
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
cni:
  exclusive: false
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

helm template cilium cilium/cilium \
  --version 1.19.1 \
  --namespace kube-system \
  -f "$CILIUM_VALUES" \
  | kubectl apply -f -

echo "      Warte auf Cilium DaemonSet..."
kubectl -n kube-system rollout status daemonset/cilium --timeout=5m

echo "      Node-Status:"
kubectl get nodes

# --- Control-Plane-Taint (Single-Node) ---
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [[ "$NODE_COUNT" -eq 1 ]]; then
  echo "      Single-Node: Control-Plane-Taint entfernen..."
  kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
fi

# --- Sealed-Secrets Master Key ---
# kube-system existiert von Anfang an — Key kann sofort gesetzt werden.
# sealed-secrets Controller (von Flux installiert) liest den Key beim Start.
echo "[2/3] Sealed-Secrets Master Key anwenden..."
if [[ -f "${REPO_ROOT}/cluster/sealed-secrets-master-key.yaml" ]]; then
  kubectl apply -f "${REPO_ROOT}/cluster/sealed-secrets-master-key.yaml"
  echo "      Key angewendet — Controller entschlüsselt SealedSecrets beim Start."
else
  echo "      WARNUNG: cluster/sealed-secrets-master-key.yaml nicht gefunden!"
  echo "               SealedSecrets können nicht entschlüsselt werden."
  echo "               Key aus Backup wiederherstellen und erneut ausführen."
fi

# --- Flux Bootstrap ---
echo "[3/3] Flux Bootstrap (Flux übernimmt ab hier alles weitere)..."
flux bootstrap github \
  --owner=Berndinox \
  --repository=k8s-homelab-gitops-v2 \
  --branch=main \
  --path=flux-system \
  --personal

# --- Ergebnis ---
echo ""
echo "=== Bootstrap abgeschlossen ==="
echo ""
echo "Flux Status:"
flux get all -A
echo ""
echo "Nächste Schritte:"
echo "  flux get kustomizations -A   # Reconciliation-Status"
echo "  flux get helmreleases -A     # HelmRelease-Status"
echo "  kubectl get nodes            # Node-Status"
