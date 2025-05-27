#!/usr/bin/env nextflow

/*
 * GWASi-flow - A Nextflow pipeline for GWAS data ingestion and processing
 */

// Default parameters
params.gwas_url = null
params.gwas_csv = null
params.outdir = 'results'

log.info """\
         GWASi-flow - GWAS INGESTION PIPELINE
         ===================================
         GWAS CSV     : ${params.gwas_csv}
         GWAS URL     : ${params.gwas_url}
         Output dir   : ${params.outdir}
         """
         .stripIndent()

// Validate inputs
if (params.gwas_url == null && params.gwas_csv == null) {
    error "Please provide either a GWAS URL with --gwas_url or a CSV file with --gwas_csv"
}

// Process 1: Download GWAS file
process downloadGWAS {
    publishDir "${params.outdir}/raw", mode: 'copy'
    
    input:
    tuple val(gwas), val(year), val(url)
    
    output:
    tuple val(meta), path("${gwas}_raw.txt"), emit: gwas_raw
    
    exec:
    meta = [gwas: gwas, year: year]
    
    script:
    """
    wget -O "${gwas}_raw.txt" ${url}
    """
}

// Process 2: Munge GWAS file using MungeSumstats
process mungeGWAS {
    publishDir "${params.outdir}/processed", mode: 'copy'
    container 'ghcr.io/haglunda/gwasi-flow:latest'
    
    input:
    tuple val(meta), path(gwas_file)
    
    output:
    tuple val(meta), path("${meta.gwas}_processed.txt"), emit: gwas_processed
    
    script:
    """
    #!/usr/bin/env Rscript
    
    # Load required libraries
    library(MungeSumstats)
    
    # Process GWAS summary statistics
    # This is a placeholder - you'll need to add your specific processing logic
    gwas_data <- MungeSumstats::read_sumstats("${gwas_file}")
    
    # Add your munging operations here
    # ...
    
    # Write processed data
    write.table(gwas_data, file="${meta.gwas}_processed.txt", quote=FALSE, row.names=FALSE, sep="\\t")
    """
}

// Workflow definition
workflow {
    if (params.gwas_csv) {
        // CSV-based workflow - read CSV file directly into a channel
        Channel
            .fromPath(params.gwas_csv)
            .splitCsv(header: true)
            .map { row -> [row.GWAS, row.year, row.URL] }
            .set { gwas_ch }
            
        downloadGWAS(gwas_ch)
        mungeGWAS(downloadGWAS.out.gwas_raw)
    } else if (params.gwas_url) {
        // Legacy single URL workflow
        Channel
            .of(['single', '', params.gwas_url])
            .set { gwas_ch }
            
        downloadGWAS(gwas_ch)
        mungeGWAS(downloadGWAS.out.gwas_raw)
    }
}
