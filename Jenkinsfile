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
            description: 'Choose deployment or rollback'
        )
        string(
            name: 'APP_VERSION',
            defaultValue: '1.3',
            description: 'Version to deploy; ignored for rollback'
        )
    }

    stages {
        stage('Validate') {
            steps {
                sh '''
                    set -eu
                    bash -n scripts/deploy.sh
                    bash -n scripts/rollback.sh
                    docker info >/dev/null
                    echo "Validation passed."
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
                    curl --fail --silent --show-error \
                        http://127.0.0.1:18080/ \
                        | grep -E 'Version:|Status: Running'

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
