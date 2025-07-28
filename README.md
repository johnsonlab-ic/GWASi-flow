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
The pipeline is run locally but also includes the `-profile imperial` for submission of jobs to PBS. You can always provide your local `.config` file to specify execution requirements.

### Docker image

The pipeline uses a Docker container with R and MungeSumstats to ensure reproducibility. The required Docker image (`ghcr.io/haglunda/gwasi-flow:latest`) is automatically pulled from GitHub Container Registry when you run the pipeline.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--gwas_csv` | Path to CSV file with GWAS information (columns: GWAS, year, path, genome_build) | null |
| `--outdir` | Directory where results will be saved | `results` |

## Input CSV Format

The input CSV file should have the following columns:
- `GWAS`: Name/identifier of the GWAS study (used for output file naming)
- `year`: Publication year of the study (for metadata)
- `path`: Path to the GWAS summary statistics file (can be URL or local file path)
- `genome_build`: Genome build of the GWAS data (must be either 'GRCh38' or 'GRCh37')

See `test/inputs/gwas_list.csv` for structure.

## Output

The pipeline produces:
- `results/raw/` - Downloaded raw GWAS files (named as `{GWAS}_raw.txt`)
- `results/processed/` - Processed GWAS files after running through MungeSumstats (named as `{GWAS}_processed{GENOME_BUILD}.txt`)

For example, with GRCh38 and GRCh37 genome builds specified in the CSV:
```
results/
├── processed/
│   ├── Epilepsy_1_processedGRCh38.txt
│   ├── Epilepsy_2_processedGRCh37.txt
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

### CHR:POS to RSID conversion

The pipeline is designed for minimal user input, including not having to know the genome build. MungeSumstats conveniently provides with a `convert_ref_genome` function, which unfortunately expects SNPs to be in "rsid" format. The pipeline here includes a check to automatically infer genome build based on chromosome and position information, and converts these to rsids for use by MungeSumstats.


You can further customize the MungeSumstats parameters and add more column name conversions by editing the `mungeGWAS` process in `main.nf`.
