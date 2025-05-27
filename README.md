# GWASi-flow

A Nextflow pipeline for GWAS data ingestion and processing.

## Overview

This pipeline performs the following steps:
1. Downloads GWAS summary statistics files from specified URLs
2. Processes the files using MungeSumstats to standardize the format

## Requirements

- [Nextflow](https://www.nextflow.io/) (v21.10.0 or later)
- [Docker](https://www.docker.com/) or [Singularity](https://sylabs.io/singularity/)

## Usage

### Run the pipeline

Using a CSV file with GWAS information:
```bash
nextflow run main.nf --gwas_csv 'path/to/your/gwas_list.csv' --outdir 'results'
```

Using a single GWAS URL (legacy mode):
```bash
nextflow run main.nf --gwas_url 'https://path/to/your/gwas/file' --outdir 'results'
```

### Docker image

The pipeline uses Docker containers to ensure reproducibility. The required Docker image is automatically pulled when you run the pipeline.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--gwas_csv` | Path to CSV file with GWAS information (columns: GWAS, year, URL) | null |
| `--gwas_url` | URL of a single GWAS summary statistics file to download (legacy mode) | null |
| `--outdir` | Directory where results will be saved | `results` |

## Input CSV Format

The input CSV file should have the following columns:
- `GWAS`: Name/identifier of the GWAS study
- `year`: Publication year of the study
- `URL`: URL or FTP link to download the GWAS summary statistics file

Example:
```
GWAS,year,URL
Height_GIANT,2018,https://example.com/height_giant.txt.gz
BMI_GIANT,2019,https://example.com/bmi_giant.txt.gz
T2D_DIAGRAM,2020,ftp://example.com/t2d_diagram.txt.gz
```

## Output

The pipeline produces:
- `results/raw/` - Downloaded raw GWAS files
- `results/processed/` - Processed GWAS files after running through MungeSumstats

## Customizing the MungeSumstats Process

Edit the `mungeGWAS` process in `main.nf` to modify how your GWAS data is processed.
