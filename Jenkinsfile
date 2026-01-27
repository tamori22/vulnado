pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        disableConcurrentBuilds()
        timeout(time: 1, unit: 'HOURS')
        buildDiscarder(logRotator(daysToKeepStr: '7', numToKeepStr: '50'))
    }

    parameters {
        booleanParam(name: 'BUILD',  defaultValue: true, description: 'Build project (mvn package)')
        booleanParam(name: 'TEST',   defaultValue: true, description: 'Run tests (mvn test)')
        booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Deploy via docker compose up -d --build')
        booleanParam(name: 'DOWN',   defaultValue: false, description: 'docker compose down at the end')
    }

    environment {
        MVN = "./mvnw"
        COMPOSE_FILE = "docker-compose.yml"
        // если нужно, можно переопределить имя проекта compose
        COMPOSE_PROJECT_NAME = "vulnado"
    }

    stages {
        stage('Checkout') {
            steps {
                PrintStage()
                checkout scm
                sh 'ls -la'
            }
        }

        stage('Gitleaks') {
            steps {
                PrintStage("Running Gitleaks secret scan (Docker)")
                sh '''
                  set -e
                  docker version >/dev/null 2>&1 || (echo "Docker is not available for Jenkins user" && exit 1)

                  docker run --rm \
                    -v "$PWD:/repo" \
                    -w /repo \
                    zricethezav/gitleaks:latest detect \
                      --source . --verbose --redact --exit-code 1 \
                      --report-format sarif --report-path gitleaks.sarif
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks.sarif', allowEmptyArchive: true
                }
            }
        }

        stage('Build') {
            when { expression { return params.BUILD } }
            steps {
                PrintStage()
                sh '''
                  set -e
                  chmod +x ./mvnw
                  ./mvnw -B -DskipTests clean package
                '''
            }
        }

        stage('Test') {
            when { expression { return params.TEST } }
            steps {
                PrintStage()
                sh '''
                  set -e
                  chmod +x ./mvnw
                  ./mvnw -B test
                '''
            }
        }

        stage('Docker Compose Deploy') {
            when { expression { return params.DEPLOY } }
            steps {
                PrintStage("Deploying via Docker Compose")
                sh '''
                  set -e

                  # покажем итоговый конфиг (очень помогает дебажить)
                  docker compose -f "${COMPOSE_FILE}" config

                  # сборка и запуск
                  docker compose -f "${COMPOSE_FILE}" up -d --build

                  echo "=== docker compose ps ==="
                  docker compose -f "${COMPOSE_FILE}" ps
                '''
            }
        }

        stage('Archive') {
            when { expression { return params.BUILD } }
            steps {
                PrintStage("Archiving build artifacts")
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true, allowEmptyArchive: true
            }
        }
    }

    post {
        always {
            junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: true

            script {
                currentBuild.result = currentBuild.result ?: 'SUCCESS'
                echo "Pipeline finished with status: ${currentBuild.result}"
            }
        }

        cleanup {
            script {
                if (params.DOWN) {
                    echo "Bringing stack down (DOWN=true)"
                    sh '''
                      set +e
                      docker compose -f "${COMPOSE_FILE}" down --remove-orphans
                    '''
                }
            }
        }
    }
}

void PrintStage(String text = "") {
    if (text?.trim()) {
        println(text)
    } else {
        println('* ' * 10 + env.STAGE_NAME.toUpperCase() + ' *' * 10)
    }
}
