# GWASi-flow

A Nextflow pipeline for GWAS data ingestion and processing.

## Overview

This pipeline performs the following steps:
1. Downloads a GWAS summary statistics file from a specified URL
2. Processes the file using MungeSumstats to standardize the format

## Requirements

- [Nextflow](https://www.nextflow.io/) (v21.10.0 or later)
- [Docker](https://www.docker.com/) or [Singularity](https://sylabs.io/singularity/)

## Usage

### Build and Push the Docker image

You can build and push the Docker image to GitHub Container Registry using the provided script:

```bash
./build_docker.sh
```

This script will:
1. Build the Docker image locally
2. Tag it for GitHub Container Registry (ghcr.io)
3. Prompt you to log in to GitHub Container Registry
4. Push the image to ghcr.io/haglunda/gwasi-flow:latest

### Run the pipeline

```bash
nextflow run main.nf --gwas_url 'https://path/to/your/gwas/file' --outdir 'results'
```

### Pull the Docker image directly

If you don't want to build the image locally, you can pull it directly from GitHub Container Registry:

```bash
docker pull ghcr.io/haglunda/gwasi-flow:latest
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--gwas_url` | URL of the GWAS summary statistics file to download | (required) |
| `--outdir` | Directory where results will be saved | `results` |

## Output

The pipeline produces:
- `results/raw/` - Downloaded raw GWAS file
- `results/processed/` - Processed GWAS file after running through MungeSumstats

## Customizing the MungeSumstats Process

Edit the `mungeGWAS` process in `main.nf` to modify how your GWAS data is processed.
