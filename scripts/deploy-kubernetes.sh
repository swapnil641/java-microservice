
#!/usr/bin/env bash
set -Eeuo pipefail
set +x

# ==========================================
# 1. Validate required Jenkins environment
# ==========================================

: "${AWS_REGION:?Missing AWS_REGION}"
: "${ECR_REGISTRY:?Missing ECR_REGISTRY}"
: "${HELLO_ECR_REPOSITORY:?Missing HELLO_ECR_REPOSITORY}"
: "${USER_ECR_REPOSITORY:?Missing USER_ECR_REPOSITORY}"
: "${APP_VERSION:?Missing APP_VERSION}"
: "${SSH_KEY_FILE:?Missing SSH_KEY_FILE}"
: "${SSH_USER:?Missing SSH_USER}"
: "${GITHUB_TOKEN:?Missing Jenkins GitHub token}"

# ==========================================
# 2. Create temporary working directory
# ==========================================

WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$WORK_DIR"
}

trap cleanup EXIT

export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

echo "======================================"
echo "Jenkins Agent Environment Diagnostics"
echo "======================================"

echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "Python version:"
python3 --version

# ==========================================
# 3. Install Ansible if not available
# ==========================================

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "Ansible not found. Installing Ansible..."

    sudo apt-get update
    sudo apt-get install -y ansible

    echo "Ansible installation completed."
fi

echo "Ansible version:"
ansible-playbook --version

# ==========================================
# 4. Verify required tools
# ==========================================

echo "Checking required tools..."

for tool in aws python3 git ansible-playbook; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: Required tool not found: $tool"
        exit 1
    fi
done

echo "All required tools are available."

# ==========================================
# 5. Clone private Ansible repository
# ==========================================

echo "Cloning private Kubernetes Ansible repository..."

cat > "$WORK_DIR/git-askpass.sh" <<'EOF'
#!/usr/bin/env bash

case "$1" in
    *Username*)
        printf '%s\n' "x-access-token"
        ;;
    *Password*)
        printf '%s\n' "$GITHUB_TOKEN"
        ;;
    *)
        exit 1
        ;;
esac
EOF

chmod 700 "$WORK_DIR/git-askpass.sh"

GIT_TERMINAL_PROMPT=0 \
GIT_ASKPASS="$WORK_DIR/git-askpass.sh" \
git clone \
    --depth 1 \
    --branch main \
    https://github.com/swapnil641/kubernetes-ansible-configuration.git \
    "$WORK_DIR/ansible"

rm -f "$WORK_DIR/git-askpass.sh"

echo "Ansible repository cloned successfully."

# ==========================================
# 6. Discover Kubernetes control-plane
# ==========================================

echo "Discovering Kubernetes control-plane..."

bash "$WORK_DIR/ansible/scripts/generate-inventory.sh" \
    > "$WORK_DIR/dynamic-inventory.ini"

echo "Dynamic inventory generated:"
cat "$WORK_DIR/dynamic-inventory.ini"

# ==========================================
# 7. Prepare versioned Kubernetes manifests
# ==========================================

echo "Preparing Kubernetes manifests..."

cp k8s/microservices.yaml "$WORK_DIR/microservices.yaml"

sed -i \
    "s|image: hello-service:latest|image: $ECR_REGISTRY/$HELLO_ECR_REPOSITORY:$APP_VERSION|" \
    "$WORK_DIR/microservices.yaml"

sed -i \
    "s|image: user-service:latest|image: $ECR_REGISTRY/$USER_ECR_REPOSITORY:$APP_VERSION|" \
    "$WORK_DIR/microservices.yaml"

echo "Kubernetes manifests prepared."

# ==========================================
# 8. Generate ECR authentication
# ==========================================

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

echo "ECR authentication configuration generated."

# ==========================================
# 9. Execute Ansible Kubernetes deployment
# ==========================================

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

# ==========================================
# 10. Deployment completed
# ==========================================

echo "======================================"
echo "Java Microservices Deployment Successful"
echo "======================================"