#!/usr/bin/env nextflow

/*
 * GWASi-flow - A Nextflow pipeline for GWAS data ingestion and processing
 */

// Default parameters
params.gwas_url = null
params.gwas_csv = null
params.outdir = 'results'
params.genome_build = 'GRCh38' // Default genome build, can be parameterized

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
    val genome_build // Default genome build, can be parameterized if needed
    
    when:
    
    output:
    tuple val(meta), path("${meta.gwas}_processed*.txt"), emit: gwas_processed
    
    script:
    """
    #!/usr/bin/env Rscript
    genome_build <- "${genome_build}"

    MungeSumstats::format_sumstats("${gwas_file}",
    save_path=paste0("${meta.gwas}_processed",genome_build,".txt"),
    ref_genome=genome_build,
    impute_beta=TRUE,
    impute_se=TRUE)
    
    """
}

// Workflow definition
workflow {
    if (params.gwas_csv) {
        // CSV-based workflow - read CSV file directly into a channel
        Channel
            .fromPath(params.gwas_csv)
            .splitCsv(header: true, strip: true)  // Added strip option to remove whitespace
            .map { row -> 
                // Add debug log to see what values we're getting
                log.info "Processing row: GWAS=${row.GWAS}, year=${row.year}, URL=${row.URL}"
                [row.GWAS?.trim(), row.year?.trim(), row.URL?.trim()]
            }
            .set { gwas_ch }
            
        downloadGWAS(gwas_ch)
        mungeGWAS(downloadGWAS.out.gwas_raw,params.genome_build)
    } else if (params.gwas_url) {
        // Legacy single URL workflow
        Channel
            .of(['single', '', params.gwas_url])
            .set { gwas_ch }
            
        downloadGWAS(gwas_ch)
        mungeGWAS(downloadGWAS.out.gwas_raw, params.genome_build)
    }
}
