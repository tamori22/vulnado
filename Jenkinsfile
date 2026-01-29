pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'RUN_SEMGREP', defaultValue: true)
    booleanParam(name: 'DEPLOY', defaultValue: true)
    booleanParam(name: 'CLEANUP', defaultValue: false)
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          echo "=== AFTER CHECKOUT (HOST) ==="
          pwd
          ls -la | head -n 40
          ls -la .git | head || true
          git status || true
        '''
      }
    }

    stage('Semgrep (report-only)') {
      when { expression { return params.RUN_SEMGREP } }
      steps {
        script {
          sh '''
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
                ls -la | head -n 60
                ls -la .git | head || true

                rm -f semgrep-report.json semgrep-report.txt || true

                semgrep scan --config p/ci --json -o semgrep-report.json > semgrep-report.txt 2>&1
                rc=$?

                echo "=== SEMGREP RC: $rc (ignored) ==="
                echo "=== SEMGREP LOG (tail) ==="
                tail -n 200 semgrep-report.txt || true

                echo "=== SEMGREP REPORT FILES ==="
                ls -la semgrep-report.json semgrep-report.txt || true

                exit 0
              '

            exit 0
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'semgrep-report.json,semgrep-report.txt',
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
    cleanup {
      script {
        if (params.CLEANUP) {
          sh 'docker compose down --remove-orphans || true'
        }
      }
    }
  }
}

