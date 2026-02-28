#!/usr/bin/env bash
# bootstrap.sh — Einmalige Cluster-Bootstrap-Schritte (Cilium + ArgoCD)
#
# Voraussetzungen:
#   - talosctl bootstrap bereits ausgeführt (Schritt 4)
#   - kubeconfig vorhanden (Schritt 5)
#   - KUBECONFIG gesetzt oder kubeconfig-Pfad unten anpassen
#
# Hinweis M920x: API-Server lauscht auf VIP 10.0.100.10 (Cluster-VLAN).
# Falls der Bootstrap-Rechner nur im MGMT-VLAN (10.0.200.x) ist:
#   sed 's|10.0.100.10|10.0.200.13|g' clusterconfig/kubeconfig > clusterconfig/kubeconfig-mgmt
#   export KUBECONFIG=$(pwd)/clusterconfig/kubeconfig-mgmt
#
# Ausführen aus dem cluster/ Verzeichnis:
#   cd cluster/
#   export KUBECONFIG=$(pwd)/clusterconfig/kubeconfig-mgmt
#   bash scripts/bootstrap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Bootstrap: Cilium + ArgoCD ==="
echo "KUBECONFIG: ${KUBECONFIG:-nicht gesetzt — bitte setzen!}"
echo ""

# --- Preflight ---
if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "ERROR: KUBECONFIG ist nicht gesetzt."
  echo "  export KUBECONFIG=\$(pwd)/clusterconfig/kubeconfig-mgmt"
  exit 1
fi

kubectl cluster-info --request-timeout=5s || {
  echo "ERROR: Kein Cluster erreichbar. KUBECONFIG prüfen."
  exit 1
}

# --- Helm Repos ---
echo "[1/5] Helm Repos hinzufügen..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update cilium argo

# --- Cilium Values ---
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
cni:
  exclusive: false    # Allow Multus CNI config alongside Cilium
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

# --- Cilium installieren ---
echo "[2/5] Cilium installieren (v1.19.1)..."
helm upgrade --install cilium cilium/cilium \
  --version 1.19.1 \
  --namespace kube-system \
  -f "$CILIUM_VALUES" \
  --wait --timeout 8m

echo "      Node-Status:"
kubectl get nodes

# --- Control-Plane-Taint (Single-Node) ---
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [[ "$NODE_COUNT" -eq 1 ]]; then
  echo "[3/5] Single-Node: Control-Plane-Taint entfernen..."
  kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
else
  echo "[3/5] Mehrere Nodes — Taint bleibt (Worker-Nodes vorhanden)"
fi

# --- ArgoCD installieren ---
echo "[4/5] ArgoCD installieren (v9.4.4)..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install argocd argo/argo-cd \
  --version 9.4.4 \
  --namespace argocd \
  --set server.insecure=true \
  --set server.service.type=LoadBalancer \
  --set "configs.cm.application\.resourceTrackingMethod=annotation" \
  --wait --timeout 8m

# --- Root App-of-Apps ---
echo "[5/5] Root App-of-Apps anwenden (GitOps übernimmt ab hier)..."
kubectl apply -f "${CLUSTER_DIR}/../kubernetes/bootstrap/root-app/application.yaml"

# --- Ergebnis ---
echo ""
echo "=== Bootstrap abgeschlossen ==="
echo ""
echo "ArgoCD Admin-Passwort:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo ""
echo ""
echo "ArgoCD LoadBalancer-IP (kann kurz dauern):"
kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
  echo "  (noch nicht vergeben — kubectl -n argocd get svc argocd-server)"
echo ""
echo "ArgoCD Apps:"
kubectl -n argocd get applications 2>/dev/null || echo "  (ArgoCD startet noch)"
