# Use a lightweight base image with bash, curl, and jq
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
  curl \
  jq \
  bash \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install IBM Cloud CLI
RUN curl -fsSL https://clis.cloud.ibm.com/install/linux | bash

# Copy your script into the container
COPY migrate-alerts.sh /usr/local/bin/migrate-alerts.sh

# Make it executable
RUN chmod +x /usr/local/bin/migrate-alerts.sh

# Set default command
ENTRYPOINT ["/usr/local/bin/migrate-alerts.sh"]
