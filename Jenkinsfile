pipeline {
    agent any

    tools {
        jdk 'jdk21'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {

        /* ===================================================== */
        /* BUILD CONFIGURATION                                   */
        /* ===================================================== */
        DOCKER_BUILDKIT = "1"

        /* ===================================================== */
        /* SONARQUBE SETTINGS                                    */
        /* ===================================================== */
        SCANNER_HOME      = tool 'sonar-scanner'
        SONAR_PROJECT_KEY = "Netflix-app"
        SONAR_HOST_URL    = "http://sonarqube.company.com"

        /* ===================================================== */
        /* DOCKER SETTINGS                                       */
        /* ===================================================== */
        DOCKER_USER   = "iamsubbu3"
        DOCKER_IMAGE  = "netflix-app"
        REGISTRY_CRED = "docker-credentials"

        /* Semantic Versioning */
        MAJOR_VERSION = "1"
        MINOR_VERSION = "0"
        PATCH_VERSION = "${BUILD_NUMBER}"

        DOCKER_TAG   = "v${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_VERSION}"
        FULL_IMAGE   = "${DOCKER_USER}/${DOCKER_IMAGE}:${DOCKER_TAG}"
        LATEST_IMAGE = "${DOCKER_USER}/${DOCKER_IMAGE}:latest"

        /* ===================================================== */
        /* KUBERNETES / EKS SETTINGS                             */
        /* ===================================================== */
        AWS_REGION     = "us-east-1"
        EKS_CLUSTER    = "subbu-cluster"
        K8S_NAMESPACE  = "subbu-1-ns"
        APP_DEPLOYMENT = "netflix-deployment"
        APP_CONTAINER  = "netflix-app"

        /* ===================================================== */
        /* NOTIFICATIONS                                         */
        /* ===================================================== */
        NOTIFY_EMAIL = "subramanyam9979@gmail.com"
    }

    triggers {
        githubPush()
    }

    stages {

        /* ===================================================== */
        /* STAGE 1 — CHECKOUT SOURCE CODE                        */
        /* ===================================================== */
        stage('Checkout') {
            steps {
                cleanWs()
                git branch: 'master',
                    url: 'https://github.com/iamsubbu3/Netflix-Clone-Devops-Project.git'
            }
        }

        /* ===================================================== */
        /* STAGE 2 — SONARQUBE STATIC ANALYSIS                   */
        /* ===================================================== */
        stage('SonarQube Scan') {
            steps {
                withSonarQubeEnv('sonar') {
                    sh """
                        ${SCANNER_HOME}/bin/sonar-scanner \
                          -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                          -Dsonar.projectName=${SONAR_PROJECT_KEY} \
                          -Dsonar.sources=.
                    """
                }
            }
        }

        /* ===================================================== */
        /* STAGE 3 — SONAR QUALITY GATE                          */
        /* ===================================================== */
        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        /* ===================================================== */
        /* STAGE 4 — DOCKER BUILD                                */
        /* ===================================================== */
        stage('Docker Build') {
            steps {
                script {
                    docker.build(
                        FULL_IMAGE,
                        "--pull " +
                        "--label build_number=${BUILD_NUMBER} " +
                        "--label git_commit=${GIT_COMMIT} " +
                        "--label project=${DOCKER_IMAGE} ."
                    )
                }
            }
        }

        /* ===================================================== */
        /* STAGE 5 — TRIVY SECURITY SCAN                         */
        /* ===================================================== */
        stage('Trivy Security Scan') {
            steps {
                script {
                    sh "trivy image --severity LOW,MEDIUM,HIGH ${FULL_IMAGE}"
                    sh "trivy image --exit-code 1 --severity CRITICAL ${FULL_IMAGE}"

                    sh "trivy image --format json -o trivy-report.json ${FULL_IMAGE}"
                    archiveArtifacts artifacts: 'trivy-report.json', fingerprint: true
                }
            }
        }

        /* ===================================================== */
        /* STAGE 6 — DOCKER PUSH                                 */
        /* ===================================================== */
        stage('Docker Push Image') {
            steps {
                script {
                    withDockerRegistry(
                        [credentialsId: REGISTRY_CRED, url: 'https://index.docker.io/v1/']
                    ) {
                        sh "docker push ${FULL_IMAGE}"
                        sh "docker tag ${FULL_IMAGE} ${LATEST_IMAGE}"
                        sh "docker push ${LATEST_IMAGE}"
                    }
                }
            }
        }

        /* ===================================================== */
        /* STAGE 7 — DEPLOY TO EKS (AUTO ROLLBACK)               */
        /* ===================================================== */

        stage('Deploy to EKS (Auto Rollback Enabled)') {
            steps {
                dir('k8s-manifests') {
                    withCredentials([
                        aws(
                            credentialsId: 'aws-keys',
                            accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                            secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                        )
                    ]) {

                        sh """
                            aws eks update-kubeconfig \
                              --region ${AWS_REGION} \
                              --name ${EKS_CLUSTER}
                        """

        /* --------- Apply base resources --------- */

                        sh "kubectl apply -n ${K8S_NAMESPACE} -f ."


        /* --------- Validate Deployment Exists --------- */
                        sh """
                            kubectl get deployment ${APP_DEPLOYMENT} \
                              -n ${K8S_NAMESPACE}
                        """


        /* --------- Update deployment image safely --------- */

                        script {
                            try {
                                sh """
                                    kubectl set image deployment/${APP_DEPLOYMENT} \
                                      ${APP_CONTAINER}=${FULL_IMAGE} \
                                      -n ${K8S_NAMESPACE}
                                """

                    /* Verify rollout */

                                sh """
                                    kubectl rollout status deployment/${APP_DEPLOYMENT} \
                                      -n ${K8S_NAMESPACE} \
                                      --timeout=180s
                                """
                    
                            } catch (err) {

                                sh """
                                    kubectl rollout undo deployment/${APP_DEPLOYMENT} \
                                      -n ${K8S_NAMESPACE}
                                """

                                sh """
                                    kubectl rollout status deployment/${APP_DEPLOYMENT} \
                                      -n ${K8S_NAMESPACE}
                                """

                                error("Deployment failed. Rolled back to previous stable version.")
                            }
                        }
                    }
                }
            }
        }
    }

    /* ===================================================== */
    /* POST BUILD ACTIONS                                    */
    /* ===================================================== */
    post {

        success {
            emailext(
                subject: "✅ SUCCESS | ${JOB_NAME} #${BUILD_NUMBER}",
                body: """
Hi Team,

✅ Pipeline executed successfully.

🔹 Job Name : ${JOB_NAME}
🔹 Build No : ${BUILD_NUMBER}

🐳 Immutable Image:
${FULL_IMAGE}

🏷️ Latest Tag:
${LATEST_IMAGE}

🔗 Jenkins Build:
${BUILD_URL}

🔗 SonarQube:
${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}

Regards,
DevOps Automation
""",
                to: "${NOTIFY_EMAIL}"
            )
        }

        failure {
            emailext(
                subject: "❌ FAILURE | ${JOB_NAME} #${BUILD_NUMBER}",
                body: """
Hi Team,

❌ Pipeline FAILED.

🔹 Job Name : ${JOB_NAME}
🔹 Build No : ${BUILD_NUMBER}

🔗 Logs:
${BUILD_URL}console

Regards,
DevOps Automation
""",
                to: "${NOTIFY_EMAIL}"
            )
        }

        always {
            echo "🧹 Cleaning only Jenkins built images..."

            sh """
                docker images --filter "label=project=${DOCKER_IMAGE}" -q | \
                xargs -r docker rmi -f || true
            """

            sh "docker image prune -f || true"
        }
    }
}
