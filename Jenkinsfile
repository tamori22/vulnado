pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  environment {
    COMPOSE_PROJECT_NAME = "vulnado"
    VULNADO_URL = "http://localhost:8081"
    CLIENT_URL  = "http://localhost:1337"
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
          # Gitleaks через docker (не требует установки в Jenkins)
          docker run --rm -v "$PWD:/repo" -w /repo zricethezav/gitleaks:latest detect --source . --verbose
        '''
      }
    }

    stage('Build & Test (Maven)') {
      steps {
        sh '''
          set -eux
          # Если в репе есть mvnw — лучше использовать его
          if [ -f "./mvnw" ]; then
            chmod +x ./mvnw
            ./mvnw -q -DskipTests=false test
          else
            # fallback если mvnw нет
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
          # На всякий случай прибираем старое
          docker compose down --remove-orphans || true

          # Собираем и поднимаем
          docker compose up -d --build

          docker compose ps
        '''
      }
    }

    stage('Smoke check') {
      steps {
        sh '''
          set -eux

          echo "Check vulnado: $VULNADO_URL"
          # 404 на / — ок, поэтому проверяем что сервер отвечает вообще (любым кодом, кроме 000)
          code=$(curl -s -o /dev/null -w "%{http_code}" "$VULNADO_URL" || true)
          echo "vulnado http_code=$code"
          if [ "$code" = "000" ]; then
            echo "Vulnado не отвечает"
            exit 1
          fi

          echo "Check client: $CLIENT_URL"
          code2=$(curl -s -o /dev/null -w "%{http_code}" "$CLIENT_URL" || true)
          echo "client http_code=$code2"
          if [ "$code2" = "000" ]; then
            echo "Client не отвечает"
            exit 1
          fi
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

