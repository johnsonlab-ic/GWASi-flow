FROM rocker/r-ver:latest

LABEL maintainer="HaglundA <HaglundA@github.com>"
LABEL description="Docker image for GWAS ingestion pipeline with MungeSumstats"
LABEL org.opencontainers.image.source="https://github.com/HaglundA/gwasi-flow"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install BiocManager
RUN R -e "install.packages('BiocManager', repos='https://cran.r-project.org')"

# Install MungeSumstats and dependencies
RUN R -e "BiocManager::install('MungeSumstats')"

# Create working directory
WORKDIR /data

# Default command
CMD ["R"]
