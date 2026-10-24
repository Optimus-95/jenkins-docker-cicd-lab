# Portfolio Screenshot Checklist

Capture genuine screenshots after the corresponding test passes. Do not fabricate or edit terminal results to imply success.

## Recommended captures

1. `01-github-repository.png`
   - GitHub repository page showing project name, description, README, and repository structure.

2. `02-jenkins-pipeline-success.png`
   - Jenkins build page showing a successful pipeline run and its stages.

3. `03-deployment-v1-2.png`
   - Console output showing the selected deployment version and successful verification.

4. `04-application-running.png`
   - Demo application in a browser showing the version currently deployed.

5. `05-container-health.png`
   - Terminal output showing the container is running and healthy.

6. `06-backup-retention.png`
   - Docker image list showing timestamped backup tags and the retention result.

7. `07-rollback-success.png`
   - Jenkins Console Output showing successful rollback and application verification.

8. `08-repository-structure.png`
   - GitHub repository file list with Jenkinsfile, Dockerfile, scripts, README, and docs.

## Capture guidance

- Capture the real screen using your operating system's screenshot tool.
- Use a readable browser zoom or terminal font size.
- Hide credentials, tokens, private URLs, personal data, and unrelated server details.
- Use generic lab hostnames and avoid production IP addresses.
- Prefer successful Jenkins Console Output and verified application responses.
- Save the approved images in this directory and embed selected images in the README when ready.
