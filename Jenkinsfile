pipeline {
    agent any

    // ── Configurable variables ──────────────────────────────────────────────
    environment {
        APP_NAME     = "secure-cicd-demo"
        IMAGE_TAG    = "${BUILD_NUMBER}"

        // Change to your registry: ECR format → 123456789.dkr.ecr.ap-south-1.amazonaws.com
        // DockerHub format → yourdockerhubusername
        REGISTRY     = "02497"

        FULL_IMAGE   = "${REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
        SONAR_URL    = "http://43.204.212.141:9000/"     // or your SonarQube server IP
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {

        // ── 1. Checkout ───────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                echo "Building branch: ${env.BRANCH_NAME} | commit: ${env.GIT_COMMIT?.take(7)}"
            }
        }

        // ── 2. Unit tests ─────────────────────────────────────────────────────
        stage('Unit tests') {
            steps {
                dir('app') {
                    sh 'mvn test'
                }
            }
            post {
                always {
                    junit 'app/target/surefire-reports/*.xml'
                }
            }
        }

        // ── 3. SonarQube SAST ─────────────────────────────────────────────────
        stage('SonarQube analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    dir('app') {
                        sh """
                            mvn sonar:sonar \
                              -Dsonar.projectKey=${APP_NAME} \
                              -Dsonar.host.url=${SONAR_URL} \
                              -Dsonar.login=${SONAR_AUTH_TOKEN}
                        """
                    }
                }
            }
        }

        // ── 4. Quality gate (blocks pipeline if SonarQube fails) ─────────────
        stage('Quality gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    // abortPipeline: true → build fails if gate is not passed
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ── 5. Docker build ───────────────────────────────────────────────────
        stage('Docker build') {
            steps {
                sh "docker build -t ${APP_NAME}:${IMAGE_TAG} ."
                echo "Image built: ${APP_NAME}:${IMAGE_TAG}"
            }
        }

        // ── 6. Trivy image scan ───────────────────────────────────────────────
        // Fails the build if any HIGH or CRITICAL CVE is found
        stage('Trivy scan') {
            steps {
                sh """
                    trivy image \
                        --exit-code 1 \
                        --severity HIGH,CRITICAL \
                        --ignore-unfixed \ 
                        --no-progress \
                        --format table \
                        --output trivy-report.txt \
                        ${APP_NAME}:${IMAGE_TAG}
                """
            }
            post {
                always {
                    // Archive the Trivy report regardless of pass/fail
                    archiveArtifacts artifacts: 'trivy-report.txt', allowEmptyArchive: true
                }
            }
        }

        // ── 7. Push to registry ───────────────────────────────────────────────
        stage('Push to registry') {
            steps {
                // 'registry-creds' is a Jenkins Username/Password credential
                // For ECR, use the Amazon ECR plugin instead
                withCredentials([usernamePassword(
                    credentialsId: 'registry-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh """
                        echo "${DOCKER_PASS}" | docker login -u "${DOCKER_USER}" --password-stdin
                        docker tag ${APP_NAME}:${IMAGE_TAG} ${FULL_IMAGE}
                        docker push ${FULL_IMAGE}
                        docker logout
                    """
                }
            }
        }

        // ── 8. Deploy to Kubernetes ───────────────────────────────────────────
        stage('Deploy to Kubernetes') {
            steps {
                withKubeConfig([credentialsId: 'kubeconfig']) {
                    sh """
                        # Inject the built image tag into the deployment manifest
                        sed 's|IMAGE_PLACEHOLDER|${FULL_IMAGE}|g' k8s/deployment.yaml | kubectl apply -f -
                        kubectl apply -f k8s/service.yaml

                        # Wait for rollout to complete (120s timeout)
                        kubectl rollout status deployment/${APP_NAME} --timeout=120s
                    """
                }
            }
        }

    }

    // ── Post-pipeline actions ─────────────────────────────────────────────────
    post {
        success {
            echo "Pipeline succeeded. Image deployed: ${FULL_IMAGE}"
            // Add Slack/email notification here if needed
        }
        failure {
            echo "Pipeline failed. Attempting rollback..."
            withKubeConfig([credentialsId: 'kubeconfig']) {
                sh "kubectl rollout undo deployment/${APP_NAME} || true"
            }
        }
        always {
            // Clean up local Docker images to save disk space on the agent
            sh "docker rmi ${APP_NAME}:${IMAGE_TAG} ${FULL_IMAGE} || true"
            cleanWs()
        }
    }
}
