pipeline {
    agent {
        label 'ec2-java-agent'
    }

    parameters {
        string(
            name: 'RELEASE_VERSION',
            defaultValue: '2.3.0',
            description: 'Enter application version (example: 2.3.0)'
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
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Source code is checked out on the temporary EC2 agent'
            }
        }

        stage('Verify Docker on EC2 Agent') {
            steps {
                sh '''
                    set -e

                    echo "Checking Docker installation..."
                    docker --version

                    echo "Checking Docker daemon..."
                    docker info

                    echo "Docker verification successful!"
                '''
            }
        }

        stage('Validate and Set Version') {
            steps {
                script {
                    env.APP_VERSION = params.RELEASE_VERSION.trim()

                    if (!(env.APP_VERSION ==~ /^[0-9]+\.[0-9]+\.[0-9]+$/)) {
                        error('Invalid version! Use format like 2.3.0 or 2.4.1')
                    }

                    env.DOCKER_IMAGE_TAG = "${env.APP_VERSION}-build-${env.BUILD_NUMBER}"

                    echo "Application version: ${env.APP_VERSION}"
                    echo "Docker image tag: ${env.DOCKER_IMAGE_TAG}"
                }

                sh '''
                    mvn -B versions:set \
                      -DnewVersion="$APP_VERSION" \
                      -DgenerateBackupPoms=false
                '''
            }
        }

        stage('Build') {
            steps {
                sh 'mvn clean package'
            }
        }

        stage('Test') {
            steps {
                sh 'mvn test'
            }
        }

        stage('Archive JAR') {
            steps {
                archiveArtifacts artifacts: 'target/*.jar',
                                 fingerprint: true
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
                      -t "$ECR_REGISTRY/$ECR_REPOSITORY:$DOCKER_IMAGE_TAG" \
                      .
                '''
            }
        }

        stage('Push Docker Image to ECR') {
            steps {
                sh '''
                    set -e

                    docker push \
                      "$ECR_REGISTRY/$ECR_REPOSITORY:$APP_VERSION"

                    docker push \
                      "$ECR_REGISTRY/$ECR_REPOSITORY:$DOCKER_IMAGE_TAG"
                '''
            }
        }
    }

    post {
        success {
            echo "Java Microservice ${env.APP_VERSION} pipeline completed successfully!"
            echo "Docker release tag: ${env.APP_VERSION}"
            echo "Docker build tag: ${env.DOCKER_IMAGE_TAG}"
        }

        failure {
            echo 'Java Microservice pipeline failed!'
        }

        always {
            sh 'docker logout "$ECR_REGISTRY" || true'
        }
    }
}