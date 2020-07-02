#!/bin/env bash

dnf -y update;


firewall-cmd --set-default-zone trusted;
firewall-cmd --reload;

setenforce 0;
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config;

modprobe overlay;
modprobe br_netfilter;
echo "br_netfilter" >> /etc/modules-load.d/br_netfilter.conf;
dnf -y install iproute-tc;

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system;

export REQUIRED_VERSION=1.18

dnf -y install 'dnf-command(copr)';
dnf -y copr enable rhcontainerbot/container-selinux;
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_8/devel:kubic:libcontainers:stable.repo;
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$REQUIRED_VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$REQUIRED_VERSION/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$REQUIRED_VERSION.repo;

dnf -y install cri-o;

sed -i 's/\/usr\/libexec\/crio\/conmon/\/usr\/bin\/conmon/' /etc/crio/crio.conf;

systemctl enable --now crio;

systemctl status crio;

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

dnf install -y kubelet-1.18* kubeadm-1.18* kubectl-1.18* --disableexcludes=kubernetes;

mkdir /var/lib/kubelet;

cat <<EOF > /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

sudo rm -f /etc/sysconfig/kubelet;

cat <<EOF > /etc/sysconfig/kubelet
KUBELET_EXTRA_ARGS=--container-runtime=remote --cgroup-driver=systemd --container-runtime-endpoint='unix:///var/run/crio/crio.sock'
EOF

sudo systemctl enable --now kubelet;
kubeadm init --pod-network-cidr=10.244.0.0/16;

kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://docs.projectcalico.org/v3.15/manifests/calico.yaml