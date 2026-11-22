pipeline {
    agent {
        label 'ec2-java-agent'
    }

    parameters {
        string(
            name: 'RELEASE_VERSION',
            defaultValue: '1.0.1',
            description: 'Enter release version (example: 1.0.1)'
        )
    }

    tools {
        jdk 'JDK21'
        maven 'Maven3'
    }

    environment {
        AWS_REGION = 'ap-southeast-2'
        ECR_REGISTRY = '828874705664.dkr.ecr.ap-southeast-2.amazonaws.com'
        ECR_REPOSITORY = 'java-microservice'

        GITHUB_REPO = 'swapnil641/java-microservice'
        GITHUB_BRANCH = 'dev'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Source code is checked out on the temporary EC2 agent'
            }
        }

        stage('Verify Build Environment') {
            steps {
                sh '''
                    set -e

                    echo "Checking Docker..."
                    docker --version
                    docker info

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
                        error('Invalid version! Use format like 1.0.0 or 2.4.1')
                    }

                    env.DOCKER_IMAGE_TAG = env.APP_VERSION

                    echo "Application Version: ${env.APP_VERSION}"
                    echo "GitHub Release Tag: ${env.APP_VERSION}"
                    echo "Docker Image Tag: ${env.DOCKER_IMAGE_TAG}"
                }

                sh '''
                    set -e

                    mvn -B versions:set \
                      -DnewVersion="$APP_VERSION" \
                      -DgenerateBackupPoms=false
                '''
            }
        }

        stage('Build') {
            steps {
                sh '''
                    set -e
                    mvn clean package
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    set -e
                    mvn test
                '''
            }
        }

        stage('Archive JAR') {
            steps {
                archiveArtifacts(
                    artifacts: 'target/*.jar',
                    fingerprint: true
                )
            }
        }

        stage('Upload JAR to S3') {
            steps {
                sh '''
                    set -e

                    aws s3 cp \
                      "target/java-microservice-${APP_VERSION}.jar" \
                      "s3://java-microservice-artifacts-2026-290952/java-microservice/${APP_VERSION}/java-microservice-${APP_VERSION}.jar" \
                      --region "$AWS_REGION" \
                      --only-show-errors

                    echo "JAR uploaded to S3 successfully!"
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
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -e

                    docker build \
                      --build-arg APP_VERSION="$APP_VERSION" \
                      -t "$ECR_REGISTRY/$ECR_REPOSITORY:$APP_VERSION" \
                      .

                    echo "Docker image built successfully!"
                '''
            }
        }

        stage('Push Docker Image to ECR') {
            steps {
                sh '''
                    set -e

                    docker push \
                      "$ECR_REGISTRY/$ECR_REPOSITORY:$APP_VERSION"

                    echo "Docker image pushed successfully!"
                '''
            }
        }

        stage('Create GitHub Release and Upload JAR') {
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

# GitHub tag uses the exact release version.
tag = version

jar_name = f"java-microservice-{version}.jar"
jar_path = f"target/{jar_name}"

api = f"https://api.github.com/repos/{repo}"


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


# Check whether the GitHub Release already exists.
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
        "name": f"Java Microservice {tag}",
        "generate_release_notes": True
    }

    release = request(
        f"{api}/releases",
        method="POST",
        data=json.dumps(payload).encode("utf-8")
    )

    print(f"Created GitHub Release {tag}")


release_id = release["id"]


# Remove an older JAR asset with the same filename.
assets = request(
    f"{api}/releases/{release_id}/assets"
)

for asset in assets:

    if asset["name"] == jar_name:

        request(
            f"{api}/releases/assets/{asset['id']}",
            method="DELETE"
        )

        print(f"Removed previous asset: {jar_name}")


# Upload the new versioned JAR.
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


print(f"Successfully uploaded {jar_name}")
print(f"GitHub Release: {tag}")
PY
                    '''
                }
            }
        }
    }

    post {

        success {
            echo "Java Microservice ${env.APP_VERSION} pipeline completed successfully!"

            emailext(
                to: 'swapnilpawar641@gmail.com',
                subject: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                mimeType: 'text/html',
                body: """
                    <h2 style="color:green;">Pipeline Successful!</h2>

                    <p><b>Project:</b> Java Microservice</p>
                    <p><b>Job:</b> ${env.JOB_NAME}</p>
                    <p><b>Build Number:</b> ${env.BUILD_NUMBER}</p>
                    <p><b>Application Version:</b> ${env.APP_VERSION}</p>

                    <p><b>GitHub Release:</b> ${env.APP_VERSION}</p>
                    <p><b>JAR:</b> java-microservice-${env.APP_VERSION}.jar</p>

                    <p><b>Docker Image:</b>
                    ${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${env.APP_VERSION}</p>

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
            echo 'Java Microservice pipeline failed!'

            emailext(
                to: 'swapnilpawar641@gmail.com',
                subject: "FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                mimeType: 'text/html',
                body: """
                    <h2 style="color:red;">Pipeline Failed!</h2>

                    <p><b>Project:</b> Java Microservice</p>
                    <p><b>Job:</b> ${env.JOB_NAME}</p>
                    <p><b>Build Number:</b> ${env.BUILD_NUMBER}</p>
                    <p><b>Build Status:</b> FAILURE</p>
                    <p><b>Application Version:</b> ${env.APP_VERSION ?: 'Not available'}</p>

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
