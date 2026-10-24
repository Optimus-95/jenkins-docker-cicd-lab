# Project 2 — Jenkins + Docker CI/CD Lab

A versioned Docker deployment pipeline using Jenkins, Docker, Bash, and Nginx. The pipeline validates the environment, builds a versioned image, deploys it, checks container health, maintains release history, and supports rollback.

## Architecture

GitHub → Jenkins Pipeline → Validate → Build image → Deploy container → Health check

If a deployment fails, the script attempts to restore the previously running image.

## Repository structure

```text
jenkins-docker-cicd-lab/
├── app/
│   └── index.html
├── backups/
├── docs/
│   ├── INSTALLATION.md
│   └── SCREENSHOTS.md
├── logs/
├── scripts/
│   ├── release-common.sh
│   ├── deploy.sh
│   └── rollback.sh
├── config.env.example
├── Dockerfile
├── Jenkinsfile
├── .gitignore
└── README.md
```

## Requirements

- Ubuntu Linux server
- A supported Jenkins LTS installation and compatible Java version
- Git and SSH access to the GitHub repository
- Docker Engine and Docker Compose plugin
- `bash` and `curl`
- Jenkins agent with Docker CLI access and permission to use the Docker daemon

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for clean-server setup.

## Jenkins job configuration

Create a Pipeline job configured to use **Pipeline script from SCM**:

- SCM: Git
- Repository: `git@github.com:Optimus-95/jenkins-docker-cicd-lab.git`
- Branch: `*/main`
- Script path: `Jenkinsfile`
- Credentials: a Jenkins-managed SSH credential authorized to access the private repository

The Jenkins agent executing the pipeline must have Docker access. The job's pipeline environment configures the image, container, port, release-history limit, and rollback-snapshot limit.

## Parameters

| Parameter | Purpose |
|---|---|
| `ACTION` | `DEPLOY` or `ROLLBACK` |
| `APP_VERSION` | New version for a deployment, e.g. `1.8` |
| `ROLLBACK_VERSION` | Optional exact release version to restore; blank selects the previous release |

## Deployment behavior

1. Validate shell syntax and Docker availability.
2. Build an immutable versioned image such as `cicd-demo-app:v1.8`.
3. Record the Git commit in the image metadata.
4. Tag the currently running image as a rollback snapshot.
5. Replace the container and wait for its Docker health check.
6. Verify the application version through HTTP.
7. Record the successful release and prune old history/snapshots according to configured limits.

Version tags already recorded in release history cannot be redeployed as new releases. Choose a new version for a new deployment.

## Rollback behavior

- Leave `ROLLBACK_VERSION` blank to select the previous release in history.
- Set `ROLLBACK_VERSION` to a version such as `1.4` to select that exact recorded release.
- The selected image must still exist locally.
- A successful rollback moves the selected release to the top of release history.
- The current image is snapshotted before the rollback attempt.
- If the replacement fails verification, the script attempts to restore the previously running image.

Rollback requires at least two releases in history. Release history is stored by default at:

`$JENKINS_HOME/.local/state/jenkins-docker-cicd-lab/releases.tsv`

The history and images are local to the Docker host. Back up the history file and required images if rollback must survive server loss.

## Defaults

- Container: `cicd-demo-app`
- Host port: `18080`
- App URL: `http://SERVER-IP:18080/`
- Rollback snapshots retained: 2
- Release-history entries retained: 10

`config.env.example` documents optional script configuration. Copy it to `config.env` only when intentionally overriding settings; do not commit private configuration or secrets. The Jenkinsfile sets its own pipeline environment, so coordinate any custom configuration with that environment.

## Verification

On the Docker host:

```bash
curl --fail http://127.0.0.1:18080/
docker ps --filter name=cicd-demo-app
docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' cicd-demo-app
docker image ls cicd-demo-app
```

A healthy deployment should report `running healthy` and show the deployed application version in the HTTP response.

## Troubleshooting

- **Docker permission denied:** confirm the Jenkins execution user can run `docker info`; restart Jenkins after changing group membership.
- **Git checkout fails:** verify the Jenkins SSH credential and GitHub repository access.
- **Health check fails:** inspect `docker logs cicd-demo-app` and the Jenkins Console Output.
- **Version already exists:** choose a new version or use the rollback action.
- **Rollback image missing:** inspect the release-history image ID and local Docker images.
- **Port conflict:** confirm nothing else is listening on host port `18080`.

## Security notes

- Do not store SSH private keys, access tokens, or passwords in Git.
- Use Jenkins Credentials for repository access.
- Restrict access to Jenkins and the Docker daemon; Docker access is highly privileged.
- Use HTTPS and appropriate network controls when exposing Jenkins or the demo application outside a lab.
- Do not use this demonstration pipeline in production without environment-specific security, availability, and recovery controls.
