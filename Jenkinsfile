pipeline {
    agent any
    options {
        timestamps()
        disableConcurrentBuilds()
    }
    environment {
        STATE_DIR = "${env.JENKINS_HOME}/.local/state/jenkins-docker-cicd-lab"
        IMAGE = "cicd-demo-app"
        CONTAINER_NAME = "cicd-demo-app"
        HOST_PORT = "18080"
        HEALTHCHECK_URL = "http://127.0.0.1:18080/"
        MAX_RELEASES = "10"
        MAX_ROLLBACK_SNAPSHOTS = "2"
    }
    parameters {
        choice(name: 'ACTION', choices: ['DEPLOY', 'ROLLBACK'],
               description: 'Deploy a new version or roll back')
        string(name: 'APP_VERSION', defaultValue: '1.7',
               description: 'New version to deploy; ignored during rollback')
        string(name: 'ROLLBACK_VERSION', defaultValue: '',
               description: 'Optional exact version to restore, e.g. 1.4; blank means previous release')
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
                    echo "Script syntax and Docker validation passed."
                '''
            }
        }
        stage('Deploy') {
            when { expression { params.ACTION == 'DEPLOY' } }
            steps {
                sh 'bash scripts/deploy.sh "$APP_VERSION"'
            }
        }
        stage('Rollback') {
            when { expression { params.ACTION == 'ROLLBACK' } }
            steps {
                sh '''
                    set -eu
                    if [ -n "$ROLLBACK_VERSION" ]; then
                        bash scripts/rollback.sh "$ROLLBACK_VERSION"
                    else
                        bash scripts/rollback.sh
                    fi
                '''
            }
        }
        stage('Verify') {
            steps {
                sh '''
                    set -eu
                    curl --fail --silent --show-error "$HEALTHCHECK_URL" |
                        tee /tmp/project2-app-response.txt
                    grep -F "Status: Running" /tmp/project2-app-response.txt
                    test "$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME")" = running
                    test "$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME")" = healthy
                    echo "Application verification passed."
                '''
            }
        }
    }
    post {
        success { echo 'CI/CD operation completed successfully.' }
        failure { echo 'Pipeline failed. Review Console Output.' }
    }
}
