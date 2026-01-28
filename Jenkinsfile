pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  environment {
    COMPOSE_PROJECT_NAME = "vulnado"
    VULNADO_URL = "http://vulnado:8080"
    CLIENT_URL  = "http://client:80"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD'
      }
    }

    stage('Docker sanity') {
      steps {
        sh '''
          set -eux
          whoami
          id
          echo "PATH=$PATH"
          docker version
          docker compose version
        '''
      }
    }

    stage('Gitleaks') {
      steps {
        sh '''
          set -eux
          docker run --rm -v "$PWD:/repo" -w /repo zricethezav/gitleaks:latest detect --source . --verbose
        '''
      }
    }

    stage('Build & Test (Maven)') {
      steps {
        sh '''
          set -eux
          if [ -f "./mvnw" ]; then
            chmod +x ./mvnw
            ./mvnw -q -DskipTests=false test
          else
            mvn -q -DskipTests=false test
          fi
        '''
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
        }
      }
    }

    stage('Compose Deploy') {
      steps {
        sh '''
          set -eux
          docker compose down --remove-orphans || true
          docker compose up -d --build
          docker compose ps
        '''
      }
    }

    stage('Smoke check') {
      steps {
        sh '''
          set -eux

          wait_url () {
            url="$1"
            name="$2"
            for i in $(seq 1 40); do
              code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || true)
              echo "[$name] try=$i code=$code url=$url"
              if [ "$code" != "000" ]; then
                echo "[$name] OK (http_code=$code)"
                return 0
              fi
              sleep 3
            done
            echo "[$name] NOT RESPONDING"
            return 1
          }

          wait_url "$VULNADO_URL" "vulnado"
          wait_url "$CLIENT_URL"  "client"
        '''
      }
    }
  }

  post {
    failure {
      sh '''
        set +e
        echo "=== docker compose ps ==="
        docker compose ps || true

        echo "=== docker compose logs (last 200 lines) ==="
        docker compose logs --tail=200 || true
      '''
    }
  }
}
