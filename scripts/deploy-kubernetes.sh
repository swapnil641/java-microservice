#!/usr/bin/env bash
set -Eeuo pipefail
set +x

: "${AWS_REGION:?Missing AWS_REGION}"
: "${ECR_REGISTRY:?Missing ECR_REGISTRY}"
: "${HELLO_ECR_REPOSITORY:?Missing HELLO_ECR_REPOSITORY}"
: "${USER_ECR_REPOSITORY:?Missing USER_ECR_REPOSITORY}"
: "${APP_VERSION:?Missing APP_VERSION}"
: "${SSH_KEY_FILE:?Missing SSH_KEY_FILE}"
: "${SSH_USER:?Missing SSH_USER}"

WORK_DIR="$(mktemp -d)"
REMOTE_DIR="/tmp/java-microservices-deploy-${BUILD_NUMBER:-manual}"
KNOWN_HOSTS="$WORK_DIR/known_hosts"

cleanup() {
    if [[ -n "${K8S_PRIVATE_IP:-}" && -n "${SSH_KEY_FILE:-}" && -n "${SSH_USER:-}" ]]; then
        ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
            "$SSH_USER@$K8S_PRIVATE_IP" \
            "rm -rf '$REMOTE_DIR'" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

SSH_OPTS=(
    -o IdentitiesOnly=yes
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o "UserKnownHostsFile=$KNOWN_HOSTS"
    -o ConnectTimeout=10
)

echo "Discovering Kubernetes control-plane EC2 instance..."

K8S_PRIVATE_IP="$(
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters \
          "Name=tag:Name,Values=kube-control-plane" \
          "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].PrivateIpAddress' \
        --output text
)"

if [[ -z "$K8S_PRIVATE_IP" || "$K8S_PRIVATE_IP" == "None" ||
      "$K8S_PRIVATE_IP" == *$'\t'* || "$K8S_PRIVATE_IP" == *' '* ]]; then
    echo "ERROR: Expected exactly one running Kubernetes control-plane instance."
    exit 1
fi

echo "Kubernetes control-plane: $K8S_PRIVATE_IP"

echo "Testing SSH connection..."

ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$SSH_USER@$K8S_PRIVATE_IP" "hostname"

echo "Preparing versioned Kubernetes manifests..."

cp k8s/microservices.yaml "$WORK_DIR/microservices.yaml"

sed -i \
    "s|image: hello-service:latest|image: $ECR_REGISTRY/$HELLO_ECR_REPOSITORY:$APP_VERSION|" \
    "$WORK_DIR/microservices.yaml"

sed -i \
    "s|image: user-service:latest|image: $ECR_REGISTRY/$USER_ECR_REPOSITORY:$APP_VERSION|" \
    "$WORK_DIR/microservices.yaml"

echo "Generating temporary ECR authentication file..."

ECR_PASSWORD="$(aws ecr get-login-password --region "$AWS_REGION")"

ECR_PASSWORD="$ECR_PASSWORD" python3 - \
    "$WORK_DIR/config.json" "$ECR_REGISTRY" <<'PY'
import base64
import json
import os
import sys

password = os.environ["ECR_PASSWORD"]
registry = sys.argv[2]
auth = base64.b64encode(f"AWS:{password}".encode()).decode()

config = {
    "auths": {
        registry: {
            "username": "AWS",
            "password": password,
            "auth": auth
        }
    }
}

with open(sys.argv[1], "w") as file:
    json.dump(config, file)
PY

unset ECR_PASSWORD
chmod 600 "$WORK_DIR/config.json"

echo "Creating remote deployment directory..."

ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$SSH_USER@$K8S_PRIVATE_IP" \
    "mkdir -p '$REMOTE_DIR' && chmod 700 '$REMOTE_DIR'"

scp -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$WORK_DIR/config.json" \
    "$WORK_DIR/microservices.yaml" \
    "$SSH_USER@$K8S_PRIVATE_IP:$REMOTE_DIR/"

echo "Creating Kubernetes namespace..."

ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$SSH_USER@$K8S_PRIVATE_IP" \
    "sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl create namespace java-microservices --dry-run=client -o yaml | sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -"

echo "Refreshing ECR image pull secret..."

ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$SSH_USER@$K8S_PRIVATE_IP" \
    "sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl create secret generic ecr-registry-secret --namespace java-microservices --from-file=.dockerconfigjson=$REMOTE_DIR/config.json --type=kubernetes.io/dockerconfigjson --dry-run=client -o yaml | sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -"

echo "Applying Kubernetes manifests..."

ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$SSH_USER@$K8S_PRIVATE_IP" \
    "sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f '$REMOTE_DIR/microservices.yaml'"

echo "Waiting for Hello Service rollout..."

ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$SSH_USER@$K8S_PRIVATE_IP" \
    "sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/hello-service -n java-microservices --timeout=240s"

echo "Waiting for User Service rollout..."

ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$SSH_USER@$K8S_PRIVATE_IP" \
    "sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/user-service -n java-microservices --timeout=240s"

echo "Checking deployed Kubernetes resources..."

ssh -i "$SSH_KEY_FILE" "${SSH_OPTS[@]}" \
    "$SSH_USER@$K8S_PRIVATE_IP" \
    "sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get deployments,pods,services -n java-microservices"

echo "Deployment completed successfully!"
