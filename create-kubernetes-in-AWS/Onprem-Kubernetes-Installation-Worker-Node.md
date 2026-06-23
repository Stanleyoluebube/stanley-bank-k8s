# On-prem Kubernetes — Worker Node Installation (REFERENCE ONLY)
#
# Run on each worker after the master is initialised. Stanley Bank
# runs on AWS EKS, not on-prem — this file is reference material only.
# Not deployed by ArgoCD.

# -----------------------------------------------------------------------------
# 1. Disable swap
# -----------------------------------------------------------------------------
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# -----------------------------------------------------------------------------
# 2. Kernel modules + sysctl (same as master)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# 3. Install containerd
# -----------------------------------------------------------------------------
sudo apt-get update
sudo apt-get install -y containerd apt-transport-https ca-certificates curl
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/ SystemdCgroup = false/ SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# -----------------------------------------------------------------------------
# 4. Install kubeadm / kubelet
# -----------------------------------------------------------------------------
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
  https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=1.30.0-00 kubeadm=1.30.0-00
sudo apt-mark hold kubelet kubeadm

# -----------------------------------------------------------------------------
# 5. Run the join command printed by `kubeadm init` on the master
# (replace the placeholder below with the real command from the master)
# -----------------------------------------------------------------------------
sudo kubeadm join <master-private-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
