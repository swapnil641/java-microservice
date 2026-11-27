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

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "Checking required tools..."

for tool in aws python3 git ansible-playbook; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: Required tool not found: $tool"
        exit 1
    }
done

echo "Cloning Kubernetes Ansible repository..."

GIT_TERMINAL_PROMPT=0 git clone \
    --depth 1 \
    --branch main \
    https://github.com/swapnil641/kubernetes-ansible-configuration.git \
    "$WORK_DIR/ansible"

echo "Discovering Kubernetes control-plane..."

bash "$WORK_DIR/ansible/scripts/generate-inventory.sh" \
    > "$WORK_DIR/dynamic-inventory.ini"

echo "Dynamic inventory generated:"
cat "$WORK_DIR/dynamic-inventory.ini"

echo "Preparing versioned Kubernetes manifest..."

cp k8s/microservices.yaml "$WORK_DIR/microservices.yaml"

sed -i \
    "s|image: hello-service:latest|image: $ECR_REGISTRY/$HELLO_ECR_REPOSITORY:$APP_VERSION|" \
    "$WORK_DIR/microservices.yaml"

sed -i \
    "s|image: user-service:latest|image: $ECR_REGISTRY/$USER_ECR_REPOSITORY:$APP_VERSION|" \
    "$WORK_DIR/microservices.yaml"

echo "Generating ECR authentication configuration..."

ECR_PASSWORD="$(aws ecr get-login-password --region "$AWS_REGION")"

ECR_PASSWORD="$ECR_PASSWORD" python3 - \
    "$WORK_DIR/config.json" "$ECR_REGISTRY" <<'PY'
import base64
import json
import os
import sys

password = os.environ["ECR_PASSWORD"]
registry = sys.argv[2]

auth = base64.b64encode(
    f"AWS:{password}".encode()
).decode()

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

echo "Starting Ansible Kubernetes deployment..."

export BUILD_NUMBER="${BUILD_NUMBER:-manual}"
export K8S_MANIFEST_SRC="$WORK_DIR/microservices.yaml"
export ECR_DOCKER_CONFIG_SRC="$WORK_DIR/config.json"

ANSIBLE_CONFIG="$WORK_DIR/ansible/ansible.cfg" \
ANSIBLE_HOST_KEY_CHECKING=False \
ansible-playbook \
    -i "$WORK_DIR/dynamic-inventory.ini" \
    "$WORK_DIR/ansible/playbooks/deploy-microservices.yml" \
    --private-key "$SSH_KEY_FILE" \
    --user "$SSH_USER"

echo "Java microservices deployment completed successfully!"
