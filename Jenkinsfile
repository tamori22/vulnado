pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'RUN_GITLEAKS',       defaultValue: true)
    booleanParam(name: 'RUN_SEMGREP',        defaultValue: true)
    booleanParam(name: 'GITLEAKS_BLOCKING',  defaultValue: false)
    booleanParam(name: 'SEMGREP_BLOCKING',   defaultValue: false)
    booleanParam(name: 'DEPLOY',             defaultValue: true)
    booleanParam(name: 'CLEANUP',            defaultValue: false)
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          echo "=== AFTER CHECKOUT (HOST) ==="
          pwd
          ls -la | head -n 60
          ls -la .git | head
          git status || true
        '''
      }
    }

    stage('Gitleaks') {
      when { expression { return params.RUN_GITLEAKS } }
      steps {
        script {
          def rc = sh(
            returnStatus: true,
            script: '''
              set +e
              docker pull zricethezav/gitleaks:latest

              docker run --rm \
                -v jenkins_home:/var/jenkins_home \
                -v jenkins_home:/src \
                -w /src/workspace/vulnado \
                zricethezav/gitleaks:latest detect \
                  --source . \
                  --report-format json \
                  --report-path gitleaks-report.json

              rc=$?
              echo "rc=$rc" > gitleaks-summary.txt
              ls -la gitleaks-report.json gitleaks-summary.txt || true
              exit $rc
            '''
          )

          def sum = sh(returnStdout: true, script: "cat gitleaks-summary.txt 2>/dev/null || true").trim()
          echo "Gitleaks summary: ${sum}"

          if (params.GITLEAKS_BLOCKING && rc != 0) {
            error("Gitleaks failed (exit=${rc}, GITLEAKS_BLOCKING=true)")
          } else if (!params.GITLEAKS_BLOCKING && rc != 0) {
            echo "GITLEAKS_BLOCKING=false → report-only (exit=${rc} ignored)"
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'gitleaks-report.json,gitleaks-summary.txt',
                           allowEmptyArchive: true,
                           fingerprint: true
        }
      }
    }

    stage('Semgrep') {
      when { expression { return params.RUN_SEMGREP } }
      steps {
        script {
          def rc = sh(
            returnStatus: true,
            script: '''
              set +e
              docker pull semgrep/semgrep:latest

              docker run --rm \
                -e HOME=/tmp \
                -e GIT_DISCOVERY_ACROSS_FILESYSTEM=1 \
                -v jenkins_home:/var/jenkins_home \
                -v jenkins_home:/src \
                -w /src/workspace/vulnado \
                semgrep/semgrep:latest sh -lc '
                  set +e
                  echo "=== SEMGREP START ==="
                  pwd
                  ls -la .git | head || true
                  git status || true

                  rm -f semgrep-report.json semgrep-report.txt semgrep-summary.txt || true

                  # JSON делаем через stdout (так надежнее)
                  semgrep scan --config p/ci --json > semgrep-report.json 2> semgrep-report.txt
                  rc=$?

                  findings=$(python - <<'"'"'PY'"'"'
import json
try:
    with open("semgrep-report.json","r",encoding="utf-8") as f:
        data=json.load(f)
    print(len(data.get("results",[])))
except Exception:
    print(-1)
PY
)

                  echo "rc=$rc findings=$findings" | tee semgrep-summary.txt

                  echo "=== SEMGREP LOG (tail) ==="
                  tail -n 120 semgrep-report.txt || true

                  echo "=== SEMGREP FILES ==="
                  ls -la semgrep-report.json semgrep-report.txt semgrep-summary.txt || true

                  # Возвращаем реальный rc наружу
                  exit $rc
                '
            '''
          )

          def sum = sh(returnStdout: true, script: "cat semgrep-summary.txt 2>/dev/null || true").trim()
          echo "Semgrep summary: ${sum}"

          int findings = 0
          def m = (sum =~ /findings=(\d+)/)
          if (m.find()) {
            findings = (m.group(1) as int)
          } else {
            echo "Could not parse findings from semgrep-summary.txt, treating as 0"
          }

          echo "Semgrep exit=${rc}, findings=${findings}"
          if (params.SEMGREP_BLOCKING && findings > 0) {
            error("Semgrep found ${findings} findings (SEMGREP_BLOCKING=true)")
          } else if (!params.SEMGREP_BLOCKING && findings > 0) {
            echo "SEMGREP_BLOCKING=false → findings present (${findings}), but not blocking"
          } else {
            echo "Semgrep: no findings (or parsing failed)."
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'semgrep-report.json,semgrep-report.txt,semgrep-summary.txt',
                           allowEmptyArchive: true,
                           fingerprint: true
        }
      }
    }

    stage('Build & Test') {
      steps {
        sh '''
          set -eux
          if [ -x ./mvnw ]; then
            ./mvnw test
          else
            mvn test
          fi
        '''
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
        }
      }
    }

    stage('Deploy (docker-compose)') {
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
  }

  post {
    always {
      archiveArtifacts artifacts: 'target/**/*.jar',
                       allowEmptyArchive: true,
                       fingerprint: true
    }

    failure {
      sh '''
        set +e
        docker compose ps || true
        docker compose logs --tail=200 || true
      '''
    }

    cleanup {
      script {
        if (params.CLEANUP) {
          sh 'docker compose down --remove-orphans || true'
        }
      }
    }
  }
}


