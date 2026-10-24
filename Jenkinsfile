pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['DEPLOY', 'ROLLBACK'],
            description: 'Deploy a version or roll back to the previous successful release'
        )
        string(
            name: 'APP_VERSION',
            defaultValue: '1.5',
            description: 'Version to deploy; ignored during rollback'
        )
    }

    stages {
        stage('Validate') {
            steps {
                sh '''
                    set -eu
                    bash -n scripts/release-common.sh
                    bash -n scripts/deploy.sh
                    bash -n scripts/rollback.sh
                    docker info >/dev/null
                    echo "Scripts and Docker validation passed."
                '''
            }
        }

        stage('Deploy') {
            when {
                expression { params.ACTION == 'DEPLOY' }
            }
            steps {
                sh '''
                    set -eu
                    bash scripts/deploy.sh "$APP_VERSION"
                '''
            }
        }

        stage('Rollback') {
            when {
                expression { params.ACTION == 'ROLLBACK' }
            }
            steps {
                sh '''
                    set -eu
                    bash scripts/rollback.sh
                '''
            }
        }

        stage('Verify') {
            steps {
                sh '''
                    set -eu

                    echo "===== APPLICATION RESPONSE ====="
                    curl --fail --silent --show-error \
                        http://127.0.0.1:18080/ \
                        | tee /tmp/project2-app-response.txt

                    grep -F "Status: Running" /tmp/project2-app-response.txt

                    echo "===== CONTAINER HEALTH ====="
                    test "$(docker inspect --format '{{.State.Status}}' cicd-demo-app)" = "running"
                    test "$(docker inspect --format '{{.State.Health.Status}}' cicd-demo-app)" = "healthy"

                    echo "Application verification passed."
                '''
            }
        }
    }

    post {
        success {
            echo 'CI/CD operation completed successfully.'
        }
        failure {
            echo 'Pipeline failed. Review Console Output.'
        }
    }
}
