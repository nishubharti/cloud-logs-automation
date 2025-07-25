# Cloud Logs Automation

This repository contains automation scripts to **migrate alerts** from one IBM Cloud® Log Analysis instance to another.

---

## Prerequisites

Before running the migration script, make sure the following are available on your system:

- [IBM Cloud CLI](https://cloud.ibm.com/docs/cli?topic=cli-install-ibmcloud-cli)
- IBM Cloud **API Key**
- **Source instance** GUID and region
- **Target instance** GUID and region
- `jq` and `curl` installed

---

## How to Run the Script Locally

1. Make the script executable:

   ```bash
   chmod +x migrate-alert.sh
   ```

2. Run the script:

   ```bash
   ./migrate-alert.sh
   ```

3. You’ll be prompted to enter:

   - Source instance GUID and region
   - Target instance GUID and region
   - IBM Cloud API key

Once provided, the script will fetch alerts from the source and migrate them to the target instance.

---

## Running with Podman (Linux)

If you are on Linux and prefer a containerized environment, use the provided **Dockerfile** to run the script with Podman:

### Step 1: Build the image

```bash
cd scripts
podman machine init
podman machine start
podman build -t alert-migrator .
```

### Step 2: Run the container

```bash
podman run -it --rm localhost/alert-migrator
```

> The container automatically installs all dependencies. During execution, you’ll be prompted for instance details and API key, just like the local version.

---

## Notes

- Alerts with event-notifications configuration will be created without event-notifiguration conifguration. the script will prompt before proceeding.
- Ensure you have sufficient permissions to access and create alerts in both instances.

