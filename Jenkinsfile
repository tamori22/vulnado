pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'RUN_GITLEAKS', defaultValue: true,  description: 'Запускать gitleaks (если false — пропускаем стадию)')
    booleanParam(name: 'DEPLOY',       defaultValue: true,  description: 'Делать docker compose up + smoke-check')
    booleanParam(name: 'CLEANUP',      defaultValue: false, description: 'После билда сделать docker compose down')
    booleanParam(name: 'PUBLISH_HTML', defaultValue: true,  description: 'Публиковать HTML-отчет (если он существует)')
    string(name: 'VULNADO_URL_OVERRIDE', defaultValue: '', description: 'Если задано — использовать этот URL вместо VULNADO_URL')
    string(name: 'CLIENT_URL_OVERRIDE',  defaultValue: '', description: 'Если задано — использовать этот URL вместо CLIENT_URL')
  }

  environment {
    COMPOSE_PROJECT_NAME = "vulnado"
    VULNADO_URL = "http://vulnado:8080"
    CLIENT_URL  = "http://client:80"
    HTML_REPORT_DIR   = "target/site"
    HTML_REPORT_INDEX = "index.html"
    HTML_REPORT_NAME  = "Project HTML Report"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD || true'
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
      when { expression { return params.RUN_GITLEAKS } }
      steps {
        sh '''
          set -eux
          docker run --rm \
            -v "$PWD:/repo" -w /repo \
            zricethezav/gitleaks:latest \
            detect --source /repo --no-git --verbose
        '''
      }
    }

stage('Semgrep') {
  steps {
    sh '''
      set -eux
      echo "WORKSPACE=$WORKSPACE"
      ls -la "$WORKSPACE"

      docker run --rm \
        -v "$WORKSPACE:/src" \
        -w /src \
        returntocorp/semgrep:latest \
        semgrep scan --config=auto .
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

    stage('Publish HTML report') {
      when { expression { return params.PUBLISH_HTML } }
      steps {
        script {
          def reportPath = "${env.HTML_REPORT_DIR}/${env.HTML_REPORT_INDEX}"
          if (fileExists(reportPath)) {
            publishHTML(target: [
              allowMissing: false,
              alwaysLinkToLastBuild: true,
              keepAll: true,
              reportDir: env.HTML_REPORT_DIR,
              reportFiles: env.HTML_REPORT_INDEX,
              reportName: env.HTML_REPORT_NAME
            ])
          } else {
            echo "HTML report not found at ${reportPath}. Skipping HTML publish."
          }
        }
      }
    }

    stage('Compose Deploy') {
      when { expression { return params.DEPLOY } }
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
      when { expression { return params.DEPLOY } }
      steps {
        sh '''
          set -eux

          VURL="${VULNADO_URL_OVERRIDE:-$VULNADO_URL}"
          CURL="${CLIENT_URL_OVERRIDE:-$CLIENT_URL}"

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

          wait_url "$VURL" "vulnado"
          wait_url "$CURL" "client"
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

    always {
      script {
        if (params.CLEANUP) {
          sh 'docker compose down --remove-orphans || true'
        } else {
          echo "CLEANUP=false, оставляю compose окружение поднятым."
        }
      }
    }
  }
}

