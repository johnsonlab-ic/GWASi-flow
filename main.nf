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
         Genome build : ${params.genome_build}
         Output dir   : ${params.outdir}
         """
         .stripIndent()

// Validate inputs
if (params.gwas_csv == null) {
    error "Please provide a CSV file with GWAS information using --gwas_csv"
}

// Process 1: Download GWAS file
process downloadGWAS {
    label "process_low"
    publishDir "${params.outdir}/raw", mode: 'copy'
    
    input:
    tuple val(gwas), val(year), val(url)
    
    output:
    tuple val(meta), path("${gwas}_raw.txt"), emit: gwas_raw
    
    exec:
    meta = [gwas: gwas, year: year]
    
    script:
    """
    # Download the file with original extension
    wget -O downloaded_file "${url}"
    
    # Check if the file is gzipped
    if file downloaded_file | grep -q gzip; then
        gunzip -c downloaded_file > "${gwas}_raw.txt"
    elif file downloaded_file | grep -q zip; then
        # Handle zip files
        unzip -p downloaded_file > "${gwas}_raw.txt"
    elif file downloaded_file | grep -q "bzip2"; then
        bunzip2 -c downloaded_file > "${gwas}_raw.txt"
    else
        # File is not compressed, just rename it
        mv downloaded_file "${gwas}_raw.txt"
    fi
    """
}

// Process 2: Munge GWAS file using MungeSumstats
process mungeGWAS {
    label "process_high"
    publishDir "${params.outdir}/processed", mode: 'copy'
    
    
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
    convert_ref_genome=genome_build,
    impute_beta=TRUE,
    impute_se=TRUE)
    
    """
}

// Workflow definition
workflow {
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
    mungeGWAS(downloadGWAS.out.gwas_raw, params.genome_build)
}
