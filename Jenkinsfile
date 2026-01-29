@Library('jenkins-shared') _
pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'RUN_GITLEAKS', defaultValue: true,  description: '')
    booleanParam(name: 'TEST_GITLEAKS', defaultValue: false, description: '')
    booleanParam(name: 'RUN_SEMGREP',  defaultValue: true,  description: '')
    booleanParam(name: 'GITLEAKS_BLOCKING', defaultValue: true, description: '')
    booleanParam(name: 'SEMGREP_BLOCKING',  defaultValue: true, description: '')
    booleanParam(name: 'DEPLOY',       defaultValue: true,  description: '')
    booleanParam(name: 'CLEANUP',      defaultValue: false, description: '')
    booleanParam(name: 'PUBLISH_HTML', defaultValue: true,  description: 'Requires HTML Publisher plugin (disabled in this Jenkinsfile)')
    string(name: 'VULNADO_URL_OVERRIDE', defaultValue: '', description: '')
    string(name: 'CLIENT_URL_OVERRIDE',  defaultValue: '', description: '')
    string(name: 'SMOKE_VULNADO_PATH', defaultValue: '/', description: 'Path to check inside vulnado container URL, e.g. /, /login, /actuator/health')
    string(name: 'SMOKE_CLIENT_PATH',  defaultValue: '/', description: 'Path to check inside client container URL')
  }

  environment {
    COMPOSE_PROJECT_NAME = "vulnado"
    VULNADO_URL = "http://vulnado:8080"
    CLIENT_URL  = "http://client:80"
    SEMGREP_APP_TOKEN = credentials('semgrep-app-token')
    HTML_REPORT_DIR   = "target/site"
    HTML_REPORT_INDEX = "index.html"
    HTML_REPORT_NAME  = "Project HTML Report"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          echo "WORKSPACE=$WORKSPACE"
          git rev-parse --short HEAD || true
          git rev-parse --abbrev-ref HEAD || true
          git branch --show-current || true
        '''
        script {
          def branch = sh(script: 'git rev-parse --abbrev-ref HEAD || true', returnStdout: true).trim()
          def sha    = sh(script: 'git rev-parse --short HEAD || true', returnStdout: true).trim()
          if (!branch) { branch = 'unknown' }
          if (!sha)    { sha = 'unknown' }
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${branch}@${sha}"
        }
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

          # (опционально) тестовый секрет
          if [ "${TEST_GITLEAKS:-false}" = "true" ]; then
            cat > "$WORKSPACE/.gitleaks_test_secret.txt" <<'EOF'
GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwxyz1234
EOF
          fi

          # gitleaks: всегда генерим json отчёт
          set +e
          docker run --rm \
            -v "$WORKSPACE:/repo" -w /repo \
            zricethezav/gitleaks:latest \
            detect --source /repo --no-git --verbose \
            --report-format json --report-path /repo/gitleaks-report.json
          rc=$?
          set -e

          echo "=== AFTER GITLEAKS ==="
          echo "PWD=$(pwd)"
          echo "WORKSPACE=$WORKSPACE"
          ls -la "$WORKSPACE" || true
          find "$WORKSPACE" -maxdepth 3 -name '*gitleaks*.json' -print -exec ls -la {} \\; || true

          rm -f "$WORKSPACE/.gitleaks_test_secret.txt" || true

          # TEST_GITLEAKS: ожидаем, что gitleaks "упадёт"
          if [ "${TEST_GITLEAKS:-false}" = "true" ]; then
            if [ $rc -ne 0 ]; then
              echo "OK: gitleaks detected the fake secret (as expected)."
              exit 0
            else
              echo "ERROR: gitleaks did NOT detect the fake secret."
              exit 1
            fi
          fi

          # Blocking vs Report-only
          if [ "${GITLEAKS_BLOCKING:-true}" = "true" ]; then
            exit $rc
          else
            echo "GITLEAKS_BLOCKING=false => report-only (ignore exit code=$rc)"
            exit 0
          fi
        '''
      }
    }

    stage('Semgrep') {
      when { expression { return params.RUN_SEMGREP } }
      steps {
        script {
          def rc = sh(
            script: '''
              set +e
              docker pull semgrep/semgrep:latest

              docker run --rm \
                -e SEMGREP_APP_TOKEN="$SEMGREP_APP_TOKEN" \
                -e GIT_DISCOVERY_ACROSS_FILESYSTEM=1 \
                -e HOME=/tmp \
                -v "$WORKSPACE:$WORKSPACE" \
                -w "$WORKSPACE" \
                semgrep/semgrep:latest sh -lc '
                  # на всякий случай (часто нужно в контейнерах)
                  git config --global --add safe.directory "$PWD" || true
                  # "как в статье"
                  semgrep ci --json -o semgrep-report.json
                '
              rc=$?
              exit $rc
            ''',
            returnStatus: true
          )

          if (rc != 0) {
            if (params.SEMGREP_BLOCKING) {
              error("Semgrep failed with exit code=${rc} (SEMGREP_BLOCKING=true)")
            } else {
              echo "SEMGREP_BLOCKING=false => report-only (ignore exit code=${rc})"
            }
          }
        }

        sh '''
          set -eux
          echo "=== AFTER SEMGREP ==="
          echo "PWD=$(pwd)"
          echo "WORKSPACE=$WORKSPACE"
          ls -la "$WORKSPACE" || true
          find "$WORKSPACE" -maxdepth 3 -name '*semgrep*.json' -print -exec ls -la {} \\; || true
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

    stage('Generate HTML report') {
      steps {
        sh '''
          set -eux
          mkdir -p target/site
          cat > target/site/index.html <<'EOF'
<html>
  <head><meta charset="utf-8"><title>Vulnado CI Report</title></head>
  <body style="font-family: Arial;">
    <h1>Vulnado CI Report</h1>
    <ul>
      <li>Build: #${BUILD_NUMBER}</li>
      <li>Job: ${JOB_NAME}</li>
      <li>Branch: $(git rev-parse --abbrev-ref HEAD || echo unknown)</li>
      <li>Commit: $(git rev-parse --short HEAD || echo unknown)</li>
    </ul>
    <p>.</p>
    <p>JUnit .</p>
  </body>
</html>
EOF
        '''
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

    stage('Smoke check (from compose network)') {
      when { expression { return params.DEPLOY } }
      steps {
        sh '''
          set -eux
          VURL="${VULNADO_URL_OVERRIDE:-$VULNADO_URL}"
          CURL="${CLIENT_URL_OVERRIDE:-$CLIENT_URL}"
          VP="${SMOKE_VULNADO_PATH:-/}"
          CP="${SMOKE_CLIENT_PATH:-/}"
          echo "VURL=$VURL"
          echo "CURL=$CURL"
          echo "SMOKE_VULNADO_PATH=$VP"
          echo "SMOKE_CLIENT_PATH=$CP"
          wait_url_in_client () {
            url="$1"
            name="$2"
            echo "=== [$name] network diagnostics (from client container) ==="
            docker compose exec -T client sh -lc 'getent hosts vulnado || true; getent hosts client || true; (nc -vz vulnado 8080 || true); (nc -vz client 80 || true)' || true

            for i in $(seq 1 40); do
              code="$(docker compose exec -T client sh -lc "curl -s -o /dev/null -w '%{http_code}' '$url' || true" | tr -d '\\r')"
              echo "[$name] try=$i code=$code url=$url"
              if [ "$code" != "000" ] && [ -n "$code" ]; then
                echo "[$name] OK (http_code=$code)"
                return 0
              fi
              sleep 3
            done
            echo "[$name] NOT RESPONDING"
            return 1
          }

          wait_url_in_client "${VURL}${VP}" "vulnado"
          wait_url_in_client "${CURL}${CP}" "client"
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
      archiveArtifacts artifacts: 'gitleaks-report.json,semgrep-report.json,target/site/**,target/**/*.jar',
                       fingerprint: true,
                       allowEmptyArchive: true

      script {
        if (params.CLEANUP) {
          sh 'docker compose down --remove-orphans || true'
        } else {
          echo "CLEANUP=false."
        }
      }
    }
  }
}



