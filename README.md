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

```bash
nextflow run johnsonlab-ic/GWASi-flow --gwas_csv 'path/to/your/gwas_list.csv' --outdir 'results'
```

### Docker image

The pipeline uses a Docker container with R and MungeSumstats to ensure reproducibility. The required Docker image (`ghcr.io/haglunda/gwasi-flow:latest`) is automatically pulled from GitHub Container Registry when you run the pipeline.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--gwas_csv` | Path to CSV file with GWAS information (columns: GWAS, year, path) | null |
| `--outdir` | Directory where results will be saved | `results` |
| `--genome_build` | Genome build to use for processing (e.g., GRCh38, GRCh37) | `GRCh38` |

## Input CSV Format

The input CSV file should have the following columns:
- `GWAS`: Name/identifier of the GWAS study (used for output file naming)
- `year`: Publication year of the study (for metadata)
- `path`: Path to the GWAS summary statistics file (can be URL or local file path)

### Data Source Types

The pipeline automatically distinguishes between URLs and local file paths in the CSV:

**For URLs** (processed with `downloadGWAS`):
```
GWAS,year,path
Epilepsy_1,2018,https://ftp.ebi.ac.uk/pub/databases/gwas/summary_statistics/GCST90271001-GCST90272000/GCST90271608/GCST90271608.tsv.gz
```

**For local file paths** (processed with `stageGWAS`):
```
GWAS,year,path
Epilepsy_2,2019,/path/to/local/gwas_file.txt.gz
Epilepsy_3,2020,./relative/path/to/gwas_file.txt
```

You can mix both URL and local file paths in the same CSV file. Local files are detected if the path starts with `/`, `./`, or `../`.


## Output

The pipeline produces:
- `results/raw/` - Downloaded raw GWAS files (named as `{GWAS}_raw.txt`)
- `results/processed/` - Processed GWAS files after running through MungeSumstats (named as `{GWAS}_processed{GENOME_BUILD}.txt`)

For example, with the default GRCh38 genome build:
```
results/
├── processed/
│   ├── Epilepsy_1_processedGRCh38.txt
│   ├── Epilepsy_2_processedGRCh38.txt
│   └── Epilepsy_3_processedGRCh38.txt
└── raw/
    ├── Epilepsy_1_raw.txt
    ├── Epilepsy_2_raw.txt
    └── Epilepsy_3_raw.txt
```

## MungeSumstats Processing

The pipeline uses the [MungeSumstats](https://github.com/neurogenomics/MungeSumstats) R package by [Murphy et al.](https://academic.oup.com/bioinformatics/article/37/23/4593/6380562) to standardize GWAS summary statistics. The current implementation:

- Validates and corrects RSIDs using the specified genome build
- Checks and corrects allele directions
- Imputes beta values and standard errors when missing
- Filters out problematic SNPs (non-biallelic, missing data, etc.)
- Standardizes column names and order

You can customize the MungeSumstats parameters by editing the `mungeGWAS` process in `main.nf`.
