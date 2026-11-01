pipeline {
    agent any

    tools {
        jdk 'JDK21'
        maven 'Maven3'
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Source code is already checked out from GitHub'
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

        stage('Get Application Version') {
            steps {
                script {
                    env.APP_VERSION = sh(
                        script: """
                            python3 -c "import xml.etree.ElementTree as E; r=E.parse('pom.xml').getroot(); ns={'m':'http://maven.apache.org/POM/4.0.0'}; print(r.findtext('m:version', namespaces=ns))"
                        """,
                        returnStdout: true
                    ).trim()

                    echo "Application version: ${env.APP_VERSION}"
                }
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
                      --region ap-southeast-2 \
                      --only-show-errors
                '''
            }
        }
    }

    post {
        success {
            echo 'Java Microservice pipeline completed successfully!'
        }

        failure {
            echo 'Java Microservice pipeline failed!'
        }
    }
}
