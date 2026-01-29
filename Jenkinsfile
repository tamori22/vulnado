pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'RUN_GITLEAKS', defaultValue: true)
    booleanParam(name: 'RUN_SEMGREP',  defaultValue: true)
    booleanParam(name: 'GITLEAKS_BLOCKING', defaultValue: true)
    booleanParam(name: 'SEMGREP_BLOCKING',  defaultValue: true)
    booleanParam(name: 'DEPLOY', defaultValue: true)
    booleanParam(name: 'CLEANUP', defaultValue: false)
  }

  environment {
    SEMGREP_APP_TOKEN = credentials('semgrep-app-token')
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
                -e SEMGREP_APP_TOKEN="$SEMGREP_APP_TOKEN" \
                -e GIT_DISCOVERY_ACROSS_FILESYSTEM=1 \
                -e HOME=/tmp \
                -v "$PWD:$PWD" \
                -w "$PWD" \
                semgrep/semgrep:latest \
                sh -lc "
                  set -eux
                  pwd
                  ls -la
                  ls -la .git
                  git status
                  semgrep ci --json -o semgrep-report.json
                "
            '''
          )

          if (rc != 0) {
            if (params.SEMGREP_BLOCKING) {
              error("Semgrep failed with exit code=${rc} (SEMGREP_BLOCKING=true)")
            } else {
              echo "SEMGREP_BLOCKING=false → report-only (exit code=${rc} ignored)"
            }
          }
        }

        sh '''
          set -eux
          echo "=== HOST AFTER SEMGREP ==="
          pwd
          ls -la
          find "$WORKSPACE" -maxdepth 3 -name '*semgrep*.json' -print -exec ls -la {} \\; || true
        '''
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
      archiveArtifacts artifacts: 'semgrep-report.json,target/**/*.jar',
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




