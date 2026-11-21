
pipeline {
    agent {
        label 'ec2-java-agent'
    }

    parameters {
        string(
            name: 'RELEASE_VERSION',
            defaultValue: '2.3.0',
            description: 'Enter application release version'
        )
    }

    tools {
        jdk 'JDK21'
        maven 'Maven3'
    }

    environment {
        AWS_REGION   = 'ap-southeast-2'
        ECR_REGISTRY = '828874705664.dkr.ecr.ap-southeast-2.amazonaws.com'
        ECR_REPO     = 'java-microservice'
        S3_BUCKET    = 'java-microservice-artifacts-2026-290952'
        APP_VERSION  = ''
        DOCKER_IMAGE_TAG = ''
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Checking out Java Microservice source code...'

                git branch: 'dev',
                    url: 'https://github.com/swapnil641/java-microservice.git'
            }
        }

        stage('Verify Docker') {
            steps {
                sh '''
                    echo "Checking Docker..."
                    docker --version
                    docker info
                '''
            }
        }

        stage('Validate and Set Version') {
            steps {
                script {
                    if (!(params.RELEASE_VERSION ==~ /^\d+\.\d+\.\d+$/)) {
                        error "Invalid version: ${params.RELEASE_VERSION}. Use format X.Y.Z"
                    }

                    env.APP_VERSION = params.RELEASE_VERSION
                    env.DOCKER_IMAGE_TAG =
                        "${env.APP_VERSION}-build-${env.BUILD_NUMBER}"

                    echo "Application Version: ${env.APP_VERSION}"
                }

                sh '''
                    mvn versions:set \
                      -DnewVersion=${APP_VERSION} \
                      -DgenerateBackupPoms=false

                    mvn help:evaluate \
                      -Dexpression=project.version \
                      -q -DforceStdout
                '''
            }
        }

        stage('Build') {
            steps {
                sh 'mvn clean package -DskipTests'
            }
        }

        stage('Test') {
            steps {
                sh 'mvn test'
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
                    aws s3 cp target/java-microservice-${APP_VERSION}.jar \
                    s3://${S3_BUCKET}/java-microservice/${APP_VERSION}/ \
                    --region ${AWS_REGION}
                '''
            }
        }

        stage('Login to Amazon ECR') {
            steps {
                sh '''
                    aws ecr get-login-password \
                    --region ${AWS_REGION} | \
                    docker login \
                    --username AWS \
                    --password-stdin ${ECR_REGISTRY}
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build \
                    -t ${ECR_REGISTRY}/${ECR_REPO}:${APP_VERSION} \
                    -t ${ECR_REGISTRY}/${ECR_REPO}:${DOCKER_IMAGE_TAG} \
                    .
                '''
            }
        }

        stage('Push Docker Image to ECR') {
            steps {
                sh '''
                    docker push ${ECR_REGISTRY}/${ECR_REPO}:${APP_VERSION}

                    docker push ${ECR_REGISTRY}/${ECR_REPO}:${DOCKER_IMAGE_TAG}
                '''
            }
        }
    }

    post {

        success {
            echo 'Java Microservice pipeline completed successfully!'

            emailext(
                to: 'swapnilpawar641@gmail.com',
                subject: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                mimeType: 'text/html',
                body: """
                    <h2 style="color:green;">Pipeline Successful</h2>

                    <p><b>Job:</b> ${env.JOB_NAME}</p>
                    <p><b>Build Number:</b> ${env.BUILD_NUMBER}</p>
                    <p><b>Release Version:</b> ${env.APP_VERSION}</p>
                    <p><b>Status:</b> SUCCESS</p>

                    <p>
                        <b>Docker Image:</b>
                        ${env.ECR_REGISTRY}/${env.ECR_REPO}:${env.APP_VERSION}
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
                    <h2 style="color:red;">Pipeline Failed</h2>

                    <p><b>Job:</b> ${env.JOB_NAME}</p>
                    <p><b>Build Number:</b> ${env.BUILD_NUMBER}</p>
                    <p><b>Status:</b> FAILURE</p>

                    <p>
                        <a href="${env.BUILD_URL}console">
                            View Jenkins Console Output
                        </a>
                    </p>
                """
            )
        }

        always {
            sh '''
                docker logout ${ECR_REGISTRY} || true
            '''

            echo 'Pipeline execution finished.'
        }
    }
}
