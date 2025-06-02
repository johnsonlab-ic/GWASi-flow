export NXF_LOG_FILE=/var/lib/docker/alex_tmp/NF_WORK/nextflow.log
workdir=/var/lib/docker/alex_tmp/NF_WORK

nextflow run main.nf \
    --gwas_csv test/inputs/gwas_list.csv -w ${workdir} 