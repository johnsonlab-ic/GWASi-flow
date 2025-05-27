#!/bin/bash
workdir=/var/lib/docker/alex_tmp/NF_WORK/
export NXF_LOG_FILE="${workdir}/nextflow.log"

# Run the pipeline with the test CSV file
nextflow run main.nf --gwas_csv test/inputs/gwas_list.csv \
-w ${workdir} 