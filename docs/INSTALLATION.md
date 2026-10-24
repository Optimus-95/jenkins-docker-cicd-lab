# Clean-Server Installation Checklist

This guide prepares a fresh Ubuntu server to run the Jenkins + Docker CI/CD lab. Run administrative commands as a sudo-enabled account. Replace example values where needed.

## 1. Update Ubuntu and install basic tools

```bash
sudo apt update
sudo apt install -y git curl ca-certificates gnupg openssh-client
```

Check the OS:

```bash
. /etc/os-release
echo "$PRETTY_NAME"
```

## 2. Install Java and Jenkins

Use a Java version supported by the Jenkins LTS release you intend to install. Recent Jenkins releases support Java 21; check the official requirements before installation.

```bash
sudo apt install -y fontconfig openjdk-21-jre
java -version
```

Install Jenkins using the current official Ubuntu/Debian instructions:
https://www.jenkins.io/doc/book/installing/linux/

Enable and verify the service:

```bash
sudo systemctl enable --now jenkins
sudo systemctl status jenkins --no-pager
```

The initial administrator password, when required for first-time setup, is available with:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Finish the setup wizard in the browser. Install the Pipeline and Git-related plugins when prompted or through Manage Jenkins → Plugins.

## 3. Install Docker Engine and Compose

Follow Docker's official Ubuntu installation guide:
https://docs.docker.com/engine/install/ubuntu/

Install Docker Engine, the Docker CLI, and the Compose plugin using the supported repository instructions for your Ubuntu release.

Verify:

```bash
docker --version
docker compose version
sudo systemctl enable --now docker
sudo docker info
```

## 4. Allow Jenkins to use Docker

The Jenkins pipeline builds and runs containers on its execution agent. If the job runs on this server, grant its Jenkins user Docker access:

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

Verify from the administrative shell:

```bash
sudo -u jenkins -H bash -c 'id; docker info'
```

If access still fails, check the Docker service, the Jenkins user's group membership, and service logs:

```bash
sudo systemctl status docker --no-pager
sudo systemctl status jenkins --no-pager
sudo journalctl -u jenkins -n 80 --no-pager
```

**Security warning:** membership in the Docker group grants highly privileged access to the host. Grant it only to trusted users and agents.

## 5. Configure GitHub SSH access

Use a dedicated SSH deploy key or another approved credential with read access to the private repository. Store credentials securely in Jenkins Credentials rather than committing them to the repository.

Repository:

```text
git@github.com:Optimus-95/jenkins-docker-cicd-lab.git
```

Test SSH authentication as the account that performs the checkout. For a Jenkins-managed credential, configure that credential in Jenkins and select it in the job's SCM configuration.

Do not disable SSH host-key checking as a general security workaround. Configure GitHub's host key using a trusted source.

## 6. Create the Jenkins Pipeline job

In Jenkins:

1. Select **New Item**.
2. Enter `Project-2-Docker-CICD`.
3. Select **Pipeline**.
4. In Pipeline, choose **Pipeline script from SCM**.
5. Set SCM to **Git**.
6. Enter the repository SSH URL above.
7. Select the Jenkins credential authorized for the repository.
8. Set the branch to `*/main`.
9. Set Script Path to `Jenkinsfile`.
10. Save and run a build.

Ensure the selected agent has Git, Bash, curl, Docker CLI, and Docker daemon access.

## 7. Verify the deployment

After a successful deployment:

```bash
curl --fail http://127.0.0.1:18080/
docker ps --filter name=cicd-demo-app
docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' cicd-demo-app
docker image ls cicd-demo-app
```

The container should be running and healthy. The HTTP response should display the deployed version.

## 8. Test rollback

Only after at least two successful releases are recorded:

- Run the Jenkins job with `ACTION=ROLLBACK` and leave `ROLLBACK_VERSION` blank to restore the previous release.
- To restore a specific recorded version, set `ROLLBACK_VERSION` to that version.
- Confirm the Jenkins build succeeds and check the HTTP response and container health again.

## 9. Persistent state and recovery

By default, release history is stored under the Jenkins user's home directory:

```text
$JENKINS_HOME/.local/state/jenkins-docker-cicd-lab/releases.tsv
```

The default snapshot retention is two images and the release-history limit is ten entries. Keep in mind that image IDs in history refer to images on the local Docker host. Server loss, image deletion, or state-file loss can affect rollback.

For production use, design and test an independent backup/recovery strategy.

## Official references

- Jenkins Linux installation: https://www.jenkins.io/doc/book/installing/linux/
- Jenkins Java requirements: https://www.jenkins.io/doc/book/platform-information/support-policy-java/
- Docker Engine on Ubuntu: https://docs.docker.com/engine/install/ubuntu/
