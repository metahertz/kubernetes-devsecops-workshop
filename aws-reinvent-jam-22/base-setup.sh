#!/usr/bin/bash
WORKSHOP_USER=ubuntu
WORKSHOP_HOMEDIR=/home/${WORKSHOP_USER}
WORKSHOP_AUTOMATION_DIR=${WORKSHOP_HOMEDIR}/.bcworkshop

mkdir -p ${WORKSHOP_AUTOMATION_DIR} || true

echo 'APT::Periodic::Update-Package-Lists "0";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Unattended-Upgrade "0";' >>  /etc/apt/apt.conf.d/20auto-upgrades

sudo apt-get update

echo "Configuring KIND cluster environment..." 
cat > ${WORKSHOP_AUTOMATION_DIR}/kind-config.yaml << EOF
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
networking:
  apiServerAddress: "0.0.0.0"
  # By default the API server listens on a random open port.
  # You may choose a specific port but probably don't need to in most cases.
  # Using a random port makes it easier to spin up multiple clusters.
  apiServerPort: 6443
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 32080
    hostPort: 32080
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 32443
    hostPort: 32443
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 30080
    hostPort: 30080
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 30081
    hostPort: 30081
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 30082
    hostPort: 30082
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 30083
    hostPort: 30083
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 30084
    hostPort: 30084
    listenAddress: "0.0.0.0"
    protocol: tcp
  - containerPort: 30085
    hostPort: 30085
    listenAddress: "0.0.0.0"
    protocol: tcp
- role: worker
- role: worker
EOF

echo "Setting up KIND cluster..."
cd ${WORKSHOP_AUTOMATION_DIR}; sudo /usr/bin/kind create cluster --name bridgecrew-workshop --config=kind-config.yaml

#echo "Installing kubectl cli..."
#curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
#chmod +x ./kubectl
#sudo mv ./kubectl /usr/bin/kubectl

echo "Providing ${WORKSHOP_USER} access to KIND cluster..."
cd ${WORKSHOP_HOMEDIR}; sudo cp -rfv /root/.kube /home/${WORKSHOP_USER}/.kube
cd ${WORKSHOP_HOMEDIR}; sudo chown -R ${WORKSHOP_USER} /home/${WORKSHOP_USER}/.kube

echo "Installing ArgoCD into cluster..."
cd ${WORKSHOP_HOMEDIR}; kubectl create namespace argocd
cd ${WORKSHOP_HOMEDIR}; kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Sprinkling some magic..."
# This is NOT a real secret (i'm looking at you checkov) it's just for a CTF "Flag"
echo "YXBpVmVyc2lvbjogdjEKa2luZDogU2VjcmV0Cm1ldGFkYXRhOgogIG5hbWU6IGRic2VjcmV0CnR5\
cGU6IE9wYXF1ZQpkYXRhOgogIFBPU1RHUkVTX1VTRVI6IFlXUnRhVzQ9CiAgUE9TVEdSRVNfUEFT\
U1dPUkQ6IFZHMVdNbHBZU1dkYU1qbDFZbTFGWjFveWJESmFVMEkxWWpOVloyUllRWE5KUnpWc1pH\
MVdlVWxIWkhaaWJUVm9TVWQ0YkdSRFFqVmlNMVZuV2tjNU0ySm5QVDA9Cg==" > ./.jank.txt
cat ./.jank.txt | base64 -d > ./.jank.manifest
cd ${WORKSHOP_HOMEDIR}; kubectl apply -f ./.jank.manifest
rm -rf ./.jank*

echo "Setting access to Argo Web UI" 
kubectl patch svc argocd-server -n argocd --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"},{"op":"replace","path":"/spec/ports/0/nodePort","value":32080},{"op":"replace","path":"/spec/ports/1/nodePort","value":32443}]'

echo "Installing ArgoCD CLI..."
#cd ${WORKSHOP_HOMEDIR}; sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
#cd ${WORKSHOP_HOMEDIR}; sudo chmod +x /usr/local/bin/argocd

echo "Installing MetalLB for Docker Bridge L2 Subnet..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
sleep 1
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
cat > ${WORKSHOP_AUTOMATION_DIR}/kind-metallb-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 172.18.255.10-172.18.255.250
EOF
kubectl apply -f ${WORKSHOP_AUTOMATION_DIR}/kind-metallb-config.yaml

echo "Installing JQ..."
sudo apt install -y jq

echo "Fixing up botocore dep version for checkov see https://github.com/aws/aws-cli/issues/3092..."
sudo apt -y remove python3-botocore
pip3 install botocore

echo "Fixup AWSCLI install.."
sudo apt install -y awscli
sudo pip3 install --upgrade awscli

echo "Pushing Kubeconfig to SSM for CI.."
sudo aws ssm put-parameter \
    --region $(curl --silent http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region) \
    --name KUBECONFIG \
    --type SecureString \
    --key-id alias/aws/ssm \
    --value "$(sudo cat /root/.kube/config | base64)" \
    --tier Advanced

echo "Sprinkling more magic..."
# This is NOT a real secret (i'm looking at you checkov) it's just for a CTF "Flag"
echo "Q29uZ3JhdHMhICBZb3UndmUgZm91bmQgYSBmbGFnClRtVjJaWElnWjI5dWJtRWdjblZ1SUdGeWIzVnVaQ0JoYm1Rc0lHUmxjMlZ5ZENCNWIzVT0K" | base64 -d >> /root/.ssh/authorized_keys

echo "done"