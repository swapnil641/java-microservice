pipeline {
    agent {
        label 'ec2-java-agent'
    }

    parameters {
        string(
            name: 'RELEASE_VERSION',
            defaultValue: '2.2.1',
            description: 'Enter release version (example: 2.2.1)'
        )
    }

    tools {
        jdk 'JDK21'
        maven 'Maven3'
    }

    environment {
        AWS_REGION = 'ap-southeast-2'
        ECR_REGISTRY = '828874705664.dkr.ecr.ap-southeast-2.amazonaws.com'

        HELLO_ECR_REPOSITORY = 'hello-service'
        USER_ECR_REPOSITORY = 'user-service'

        GITHUB_REPO = 'swapnil641/java-microservice'
        GITHUB_BRANCH = 'dev'

        S3_BUCKET = 'java-microservice-artifacts-2026-290952'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Source code is checked out on the EC2 agent'
            }
        }

        stage('Verify Build Environment') {
            steps {
                sh '''
                    set -e

                    echo "Checking Java..."
                    java -version

                    echo "Checking Maven..."
                    mvn -version

                    echo "Checking Docker..."
                    docker --version
                    docker info

                    echo "Checking AWS CLI..."
                    aws --version

                    echo "Checking Python..."
                    python3 --version

                    echo "Environment verification successful!"
                '''
            }
        }

        stage('Validate and Set Version') {
            steps {
                script {
                    env.APP_VERSION = params.RELEASE_VERSION.trim()

                    if (!(env.APP_VERSION ==~ /^[0-9]+\.[0-9]+\.[0-9]+$/)) {
                        error('Invalid version! Use format like 2.2.1')
                    }

                    echo "Application Version: ${env.APP_VERSION}"
                }

                sh '''
                    set -e

                    mvn -B versions:set \
                      -DnewVersion="$APP_VERSION" \
                      -DgenerateBackupPoms=false \
                      -DprocessAllModules=true

                    echo "Project versions updated successfully!"
                '''
            }
        }

        stage('Build and Test All Services') {
            steps {
                sh '''
                    set -e

                    mvn clean verify

                    echo "All services built and tested successfully!"
                '''
            }
        }

        stage('Verify Service JARs') {
            steps {
                sh '''
                    set -e

                    HELLO_JAR="hello-service/target/hello-service-${APP_VERSION}.jar"
                    USER_JAR="user-service/target/user-service-${APP_VERSION}.jar"

                    test -f "$HELLO_JAR"
                    test -f "$USER_JAR"

                    echo "Hello Service JAR:"
                    ls -lh "$HELLO_JAR"

                    echo "User Service JAR:"
                    ls -lh "$USER_JAR"
                '''
            }
        }

        stage('Archive Service JARs') {
            steps {
                archiveArtifacts(
                    artifacts: 'hello-service/target/*.jar,user-service/target/*.jar',
                    fingerprint: true
                )
            }
        }

        stage('Upload Service JARs to S3') {
            steps {
                sh '''
                    set -e

                    HELLO_JAR="hello-service/target/hello-service-${APP_VERSION}.jar"
                    USER_JAR="user-service/target/user-service-${APP_VERSION}.jar"

                    aws s3 cp \
                      "$HELLO_JAR" \
                      "s3://${S3_BUCKET}/hello-service/${APP_VERSION}/hello-service-${APP_VERSION}.jar" \
                      --region "$AWS_REGION" \
                      --only-show-errors

                    aws s3 cp \
                      "$USER_JAR" \
                      "s3://${S3_BUCKET}/user-service/${APP_VERSION}/user-service-${APP_VERSION}.jar" \
                      --region "$AWS_REGION" \
                      --only-show-errors

                    echo "Both service JARs uploaded to S3!"
                '''
            }
        }

        stage('Verify ECR Repositories') {
            steps {
                sh '''
                    set -e

                    aws ecr describe-repositories \
                      --repository-names "$HELLO_ECR_REPOSITORY" "$USER_ECR_REPOSITORY" \
                      --region "$AWS_REGION"

                    echo "Both ECR repositories exist!"
                '''
            }
        }

        stage('Login to Amazon ECR') {
            steps {
                sh '''
                    set -e

                    aws ecr get-login-password \
                      --region "$AWS_REGION" |
                    docker login \
                      --username AWS \
                      --password-stdin \
                      "$ECR_REGISTRY"

                    echo "ECR login successful!"
                '''
            }
        }

        stage('Build Hello Service Docker Image') {
            steps {
                sh '''
                    set -e

                    docker build \
                      --build-arg APP_VERSION="$APP_VERSION" \
                      -f hello-service/Dockerfile \
                      -t "$ECR_REGISTRY/$HELLO_ECR_REPOSITORY:$APP_VERSION" \
                      .

                    echo "Hello Service Docker image built!"
                '''
            }
        }

        stage('Build User Service Docker Image') {
            steps {
                sh '''
                    set -e

                    docker build \
                      --build-arg APP_VERSION="$APP_VERSION" \
                      -f user-service/Dockerfile \
                      -t "$ECR_REGISTRY/$USER_ECR_REPOSITORY:$APP_VERSION" \
                      .

                    echo "User Service Docker image built!"
                '''
            }
        }

        stage('Push Docker Images to ECR') {
            steps {
                sh '''
                    set -e

                    docker push \
                      "$ECR_REGISTRY/$HELLO_ECR_REPOSITORY:$APP_VERSION"

                    docker push \
                      "$ECR_REGISTRY/$USER_ECR_REPOSITORY:$APP_VERSION"

                    echo "Both Docker images pushed to ECR!"
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'java-microservice-ssh-key',
                        keyFileVariable: 'SSH_KEY_FILE',
                        usernameVariable: 'SSH_USER'
                    )
                ]) {
                    sh '''
                        set -e

                        echo "Starting Kubernetes deployment..."

                        bash scripts/deploy-kubernetes.sh
                    '''
                }
            }
        }

        stage('Create GitHub Release and Upload JARs') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'github-release-token',
                        variable: 'GITHUB_TOKEN'
                    )
                ]) {
                    sh '''
                        set -e

                        python3 - <<'PY'
import json
import os
import urllib.error
import urllib.parse
import urllib.request

repo = os.environ["GITHUB_REPO"]
version = os.environ["APP_VERSION"]
branch = os.environ["GITHUB_BRANCH"]
token = os.environ["GITHUB_TOKEN"]

api = f"https://api.github.com/repos/{repo}"
tag = version


def request(url, method="GET", data=None,
            content_type="application/json"):

    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28"
    }

    if data is not None:
        headers["Content-Type"] = content_type

    req = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method=method
    )

    with urllib.request.urlopen(req, timeout=60) as response:
        body = response.read()
        return json.loads(body) if body else {}


# Find or create the GitHub Release.
tag_url = (
    f"{api}/releases/tags/"
    f"{urllib.parse.quote(tag, safe='')}"
)

try:
    release = request(tag_url)
    print(f"Release {tag} already exists.")

except urllib.error.HTTPError as error:

    if error.code != 404:
        raise

    payload = {
        "tag_name": tag,
        "target_commitish": branch,
        "name": f"Java Microservices {tag}",
        "generate_release_notes": True
    }

    release = request(
        f"{api}/releases",
        method="POST",
        data=json.dumps(payload).encode("utf-8")
    )

    print(f"Created GitHub Release {tag}")


release_id = release["id"]


# Upload both service JARs.
artifacts = [
    (
        f"hello-service/target/hello-service-{version}.jar",
        f"hello-service-{version}.jar"
    ),
    (
        f"user-service/target/user-service-{version}.jar",
        f"user-service-{version}.jar"
    )
]


# Get existing release assets.
assets = request(
    f"{api}/releases/{release_id}/assets"
)


for jar_path, jar_name in artifacts:

    if not os.path.isfile(jar_path):
        raise FileNotFoundError(jar_path)

    # Remove an existing asset with the same filename.
    for asset in assets:

        if asset["name"] == jar_name:

            request(
                f"{api}/releases/assets/{asset['id']}",
                method="DELETE"
            )

            print(f"Removed previous asset: {jar_name}")

    upload_url = (
        f"https://uploads.github.com/repos/{repo}/releases/"
        f"{release_id}/assets?name={urllib.parse.quote(jar_name)}"
    )

    with open(jar_path, "rb") as jar:

        request(
            upload_url,
            method="POST",
            data=jar.read(),
            content_type="application/java-archive"
        )

    print(f"Uploaded {jar_name}")


print(f"GitHub Release completed: {tag}")
PY
                    '''
                }
            }
        }
    }

    post {

        success {
            echo "Java Microservices pipeline ${env.APP_VERSION} completed successfully!"

            emailext(
                to: 'swapnilpawar641@gmail.com',
                subject: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                mimeType: 'text/html',
                body: """
                    <h2 style="color:green;">Pipeline Successful!</h2>

                    <p><b>Project:</b> Java Microservices</p>
                    <p><b>Build:</b> ${env.BUILD_NUMBER}</p>
                    <p><b>Version:</b> ${env.APP_VERSION}</p>

                    <h3>Services</h3>
                    <p>Hello Service: ${env.ECR_REGISTRY}/${env.HELLO_ECR_REPOSITORY}:${env.APP_VERSION}</p>
                    <p>User Service: ${env.ECR_REGISTRY}/${env.USER_ECR_REPOSITORY}:${env.APP_VERSION}</p>

                    <p><b>S3:</b> Both service JARs uploaded successfully.</p>
                    <p><b>Kubernetes:</b> Deployment stage completed successfully.</p>

                    <p>
                        <a href="https://github.com/${env.GITHUB_REPO}/releases/tag/${env.APP_VERSION}">
                            View GitHub Release
                        </a>
                    </p>

                    <p>
                        <a href="${env.BUILD_URL}">
                            View Jenkins Build
                        </a>
                    </p>
                """
            )
        }

        failure {
            echo 'Java Microservices pipeline failed!'

            emailext(
                to: 'swapnilpawar641@gmail.com',
                subject: "FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                mimeType: 'text/html',
                body: """
                    <h2 style="color:red;">Pipeline Failed!</h2>

                    <p><b>Project:</b> Java Microservices</p>
                    <p><b>Job:</b> ${env.JOB_NAME}</p>
                    <p><b>Build Number:</b> ${env.BUILD_NUMBER}</p>
                    <p><b>Version:</b> ${env.APP_VERSION ?: 'Not available'}</p>

                    <p>
                        <a href="${env.BUILD_URL}console">
                            View Jenkins Console Output
                        </a>
                    </p>
                """
            )
        }

        always {
            sh 'docker logout "$ECR_REGISTRY" || true'

            echo 'Pipeline execution finished.'
        }
    }
}
