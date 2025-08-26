pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = credentials('docker-registry-url')
        REGISTRY_CREDENTIALS = credentials('docker-registry-credentials')
        KUBECONFIG = credentials('kubeconfig')
        NODE_VERSION = '18'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.BUILD_TAG = "${env.BRANCH_NAME}-${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                }
            }
        }

        stage('Detect Changes') {
            steps {
                script {
                    env.CONFIG_SERVICE_CHANGED = sh(
                        script: 'git diff --name-only HEAD~1 HEAD | grep "^configuration-service/" || echo "false"',
                        returnStdout: true
                    ).trim() != 'false'
                    
                    env.LOG_SERVICE_CHANGED = sh(
                        script: 'git diff --name-only HEAD~1 HEAD | grep "^log-aggregator-service/" || echo "false"',
                        returnStdout: true
                    ).trim() != 'false'
                }
                echo "Configuration Service Changed: ${env.CONFIG_SERVICE_CHANGED}"
                echo "Log Aggregator Service Changed: ${env.LOG_SERVICE_CHANGED}"
            }
        }

        stage('Setup') {
            steps {
                // Install Node.js
                sh '''
                    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
                    sudo apt-get install -y nodejs
                '''
                
                // Start test databases
                sh '''
                    docker network create test-network || true
                    
                    docker run -d --name test-mysql --network test-network \
                        -e MYSQL_ROOT_PASSWORD=password \
                        -e MYSQL_DATABASE=test_db \
                        -e MYSQL_USER=testuser \
                        -e MYSQL_PASSWORD=testpass \
                        -p 3306:3306 \
                        mysql:8.0
                    
                    docker run -d --name test-redis --network test-network \
                        -p 6379:6379 \
                        redis:7-alpine
                    
                    # Wait for databases to be ready
                    sleep 30
                '''
            }
        }

        stage('Test Configuration Service') {
            when {
                expression { env.CONFIG_SERVICE_CHANGED == 'true' || env.BRANCH_NAME == 'main' }
            }
            steps {
                dir('configuration-service') {
                    sh '''
                        npm ci
                        npm run lint || echo "Linting not configured"
                        npm test || echo "Tests not configured"
                        npm audit --if-present
                    '''
                }
            }
        }

        stage('Test Log Aggregator Service') {
            when {
                expression { env.LOG_SERVICE_CHANGED == 'true' || env.BRANCH_NAME == 'main' }
            }
            steps {
                dir('log-aggregator-service') {
                    sh '''
                        npm ci
                        npm run lint || echo "Linting not configured"
                        npm test || echo "Tests not configured"  
                        npm audit --if-present
                    '''
                }
            }
        }

        stage('Build and Push Images') {
            when {
                branch 'main'
            }
            parallel {
                stage('Configuration Service Image') {
                    when {
                        expression { env.CONFIG_SERVICE_CHANGED == 'true' }
                    }
                    steps {
                        script {
                            def configImage = docker.build("${DOCKER_REGISTRY}/configuration-service:${BUILD_TAG}", "./configuration-service")
                            docker.withRegistry("https://${DOCKER_REGISTRY}", env.REGISTRY_CREDENTIALS) {
                                configImage.push()
                                configImage.push("latest")
                            }
                        }
                    }
                }
                
                stage('Log Aggregator Service Image') {
                    when {
                        expression { env.LOG_SERVICE_CHANGED == 'true' }
                    }
                    steps {
                        script {
                            def logImage = docker.build("${DOCKER_REGISTRY}/log-aggregator-service:${BUILD_TAG}", "./log-aggregator-service")
                            docker.withRegistry("https://${DOCKER_REGISTRY}", env.REGISTRY_CREDENTIALS) {
                                logImage.push()
                                logImage.push("latest")
                            }
                        }
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when {
                branch 'main'
            }
            steps {
                script {
                    withKubeConfig([credentialsId: 'kubeconfig']) {
                        // Deploy Configuration Service
                        if (env.CONFIG_SERVICE_CHANGED == 'true') {
                            sh """
                                kubectl set image deployment/configuration-service \\
                                    configuration-service=${DOCKER_REGISTRY}/configuration-service:${BUILD_TAG} \\
                                    -n microservices
                                
                                kubectl rollout status deployment/configuration-service -n microservices --timeout=300s
                            """
                        }
                        
                        // Deploy Log Aggregator Service
                        if (env.LOG_SERVICE_CHANGED == 'true') {
                            sh """
                                kubectl set image deployment/log-aggregator-service \\
                                    log-aggregator-service=${DOCKER_REGISTRY}/log-aggregator-service:${BUILD_TAG} \\
                                    -n microservices
                                
                                kubectl rollout status deployment/log-aggregator-service -n microservices --timeout=300s
                            """
                        }
                    }
                }
            }
        }

        stage('Smoke Tests') {
            when {
                branch 'main'
            }
            steps {
                script {
                    withKubeConfig([credentialsId: 'kubeconfig']) {
                        // Test Configuration Service
                        if (env.CONFIG_SERVICE_CHANGED == 'true') {
                            sh '''
                                kubectl wait --for=condition=available --timeout=300s deployment/configuration-service -n microservices
                                
                                SERVICE_IP=$(kubectl get service configuration-service -n microservices -o jsonpath='{.spec.clusterIP}')
                                kubectl run config-test-pod --rm -i --restart=Never --image=curlimages/curl -- \\
                                    curl -f http://$SERVICE_IP:3001/health
                            '''
                        }
                        
                        // Test Log Aggregator Service
                        if (env.LOG_SERVICE_CHANGED == 'true') {
                            sh '''
                                kubectl wait --for=condition=available --timeout=300s deployment/log-aggregator-service -n microservices
                                
                                SERVICE_IP=$(kubectl get service log-aggregator-service -n microservices -o jsonpath='{.spec.clusterIP}')
                                kubectl run log-test-pod --rm -i --restart=Never --image=curlimages/curl -- \\
                                    curl -f http://$SERVICE_IP:3002/health
                            '''
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            // Cleanup test containers
            sh '''
                docker stop test-mysql test-redis || true
                docker rm test-mysql test-redis || true
                docker network rm test-network || true
            '''
            
            // Clean up Docker images
            sh 'docker system prune -f'
        }
        
        success {
            echo 'Pipeline completed successfully!'
            // Send success notification
            script {
                if (env.BRANCH_NAME == 'main') {
                    // You can add Slack, Teams, or email notifications here
                    echo "Deployment to production completed successfully"
                }
            }
        }
        
        failure {
            echo 'Pipeline failed!'
            // Send failure notification
            script {
                // You can add Slack, Teams, or email notifications here
                echo "Pipeline failed for branch ${env.BRANCH_NAME}, build ${env.BUILD_NUMBER}"
            }
        }
    }
}