#!/usr/bin/env bash
# Single-node Kubernetes cluster bootstrap (REFERENCE ONLY)
#
# Stanley Bank runs on AWS EKS, not a single-node kubeadm cluster.
# This script is kept here as reference for the kubeadm pattern.
# Not deployed by ArgoCD. Do not run in production.
set -euo pipefail

# --- preflight ---------------------------------------------------------------
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# --- containerd --------------------------------------------------------------
sudo apt-get update
sudo apt-get install -y containerd apt-transport-https ca-certificates curl
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/ SystemdCgroup = false/ SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# --- kubeadm / kubelet / kubectl --------------------------------------------
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
  https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=1.30.0-00 kubeadm=1.30.0-00 kubectl=1.30.0-00
sudo apt-mark hold kubelet kubeadm kubectl

# --- init (single-node control plane) ---------------------------------------
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

# --- allow workloads on the control plane (single-node) ---------------------
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# --- Calico CNI -------------------------------------------------------------
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

echo "Cluster ready. Test with: kubectl get nodes"
