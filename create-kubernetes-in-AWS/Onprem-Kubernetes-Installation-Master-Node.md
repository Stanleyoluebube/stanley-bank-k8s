# On-prem Kubernetes — Master Node Installation (REFERENCE ONLY)
#
# Stanley Bank runs on AWS EKS, not on-prem. The notes below are
# reference material for installing kubeadm-based clusters on bare
# metal or VMs (Ubuntu 22.04 LTS). Not deployed by ArgoCD.
#
# -----------------------------------------------------------------------------
# 1. Disable swap (kubelet requires it disabled)
# -----------------------------------------------------------------------------
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# -----------------------------------------------------------------------------
# 2. Load required kernel modules
# -----------------------------------------------------------------------------
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# -----------------------------------------------------------------------------
# 3. Set sysctl params (required for networking)
# -----------------------------------------------------------------------------
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# -----------------------------------------------------------------------------
# 4. Install containerd
# -----------------------------------------------------------------------------
sudo apt-get update
sudo apt-get install -y containerd apt-transport-https ca-certificates curl

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/ SystemdCgroup = false/ SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# -----------------------------------------------------------------------------
# 5. Install kubeadm / kubelet / kubectl (1.30)
# -----------------------------------------------------------------------------
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
  https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=1.30.0-00 kubeadm=1.30.0-00 kubectl=1.30.0-00
sudo apt-mark hold kubelet kubeadm kubectl

# -----------------------------------------------------------------------------
# 6. Initialise the control plane
# -----------------------------------------------------------------------------
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# -----------------------------------------------------------------------------
# 7. Install a CNI (Calico)
# -----------------------------------------------------------------------------
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# -----------------------------------------------------------------------------
# 8. Get the worker join command (run on each worker)
# -----------------------------------------------------------------------------
kubeadm token create --print-join-command
