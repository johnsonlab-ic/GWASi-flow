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
         Output dir   : ${params.outdir}
         """
         .stripIndent()

// Validate inputs
if (params.gwas_csv == null) {
    error "Please provide a CSV file with GWAS information using --gwas_csv"
}

// Process 1: Download GWAS file from URL
process downloadGWAS {
    label "process_low"
    tag "$gwas" 
    publishDir "${params.outdir}/raw", mode: 'copy'
    
    input:
    tuple val(gwas), val(year), val(url)
    
    output:
    tuple val(meta), path("${gwas}_raw.txt"), emit: gwas_raw
    
    exec:
    meta = [gwas: gwas, year: year]
    
    script:
    """
    # Download the file from URL
    echo "Downloading from URL: ${url}"
    wget -O downloaded_file "${url}"
    
    # Determine file type and decompress if needed
    if file downloaded_file | grep -q gzip; then
        echo "Decompressing gzip file"
        gzip -dc downloaded_file > "${gwas}_raw.txt"
    elif file downloaded_file | grep -q zip; then
        echo "Extracting zip file"
        unzip -p downloaded_file > "${gwas}_raw.txt"
    elif file downloaded_file | grep -q bzip2; then
        echo "Decompressing bzip2 file"
        bzip2 -dc downloaded_file > "${gwas}_raw.txt"
    elif [[ "${url}" == *.gz ]]; then
        echo "URL has .gz extension, forcing gzip decompression"
        gzip -dc downloaded_file > "${gwas}_raw.txt" || cp downloaded_file "${gwas}_raw.txt"
    else
        echo "Using file as-is"
        cp downloaded_file "${gwas}_raw.txt"
    fi
    
    # Verify output file exists
    if [ -s "${gwas}_raw.txt" ]; then
        echo "Successfully created output file"
    else
        echo "Warning: Output file may be empty"
    fi
    """
}

// Process 2: Stage local GWAS file (runs locally without container)
process stageGWAS {
    label "process_single"
    tag "$gwas"  // Tag process with GWAS name for easier tracking
    publishDir "${params.outdir}/raw", mode: 'copy'
    executor 'local'  // Force execution on local machine
    container null    // Disable container for this process
    
    input:
    tuple val(gwas), val(year), path(local_file)  // Using path type for proper file staging
    
    output:
    tuple val(meta), path("${gwas}_raw.txt"), emit: gwas_raw
    
    exec:
    meta = [gwas: gwas, year: year]
    
    script:
    """
    # Process local file
    echo "Staging local file: ${local_file}"
    
    # More robust file type detection and decompression
    if file "${local_file}" | grep -q gzip; then
        echo "Detected gzip file, decompressing..."
        gzip -cd "${local_file}" > "${gwas}_raw.txt"
    elif file "${local_file}" | grep -q zip; then
        echo "Detected zip file, extracting..."
        unzip -p "${local_file}" > "${gwas}_raw.txt"
    elif file "${local_file}" | grep -q bzip2; then
        echo "Detected bzip2 file, decompressing..."
        bzip2 -cd "${local_file}" > "${gwas}_raw.txt"
    elif [[ "${local_file}" == *.gz || "${local_file}" == *.gzip ]]; then
        echo "Filename has .gz extension, forcing gzip decompression"
        gzip -cd "${local_file}" > "${gwas}_raw.txt" || cp "${local_file}" "${gwas}_raw.txt"
    else
        echo "Assuming uncompressed file, copying directly..."
        cp "${local_file}" "${gwas}_raw.txt"
    fi
    
    # Verify output file exists
    if [ -s "${gwas}_raw.txt" ]; then
        echo "Successfully created output file"
    else
        echo "Warning: Output file may be empty"
    fi
    """
}

// Process 2: Munge GWAS file using MungeSumstats
process mungeGWAS {
    label "process_high"
    tag "$gwas_file"
    publishDir "${params.outdir}/processed", mode: 'copy'
    
    
    input:
    tuple val(meta), path(gwas_file), val(genome_build)
    
    output:
    tuple val(meta), path("${meta.gwas}_processed*.txt"), emit: gwas_processed
    
    script:
    """
    #!/usr/bin/env Rscript
    
    # Load required libraries
    library(data.table)
    
    # Set variables
    genome_build <- "${genome_build}"
    inputFile <- "${gwas_file}"
    outputFile <- paste0("${meta.gwas}_processed", genome_build, ".txt")
    
    # Check if the file has headers to convert
    cat("Checking file headers for standardization...\n")
    
    # Read first few lines to check headers (efficient for large files)
    fileHeader <- fread(inputFile, nrows = 1, fill = TRUE, verbose = TRUE)
    columnNames <- names(fileHeader)
    
    # Print original column names
    cat("Original column names:", paste(columnNames, collapse = ", "), "\\n")

    # Process with MungeSumstats directly
    cat("Processing with MungeSumstats...\\n")
    cat("Build is: ", genome_build, "\\n" )
    MungeSumstats::format_sumstats(
        inputFile,
        save_path = outputFile,
        impute_beta = TRUE,
        impute_se = TRUE,
        ref_genome = genome_build
    )

    if(genome_build != "GRCh38") {
       message("Warning: Genome build is not GRCh38, please ensure compatibility with your analysis.\\n")
        MungeSumstats::format_sumstats(
            outputFile,
            save_path = outputFile,
            impute_beta = TRUE,
            impute_se = TRUE,
    
            ref_genome = genome_build,
            convert_n_int = FALSE,
            convert_ref_genome = "GRCh38"
        )
    }
    """
}

// Workflow definition
workflow {
    // Read CSV file and split into two channels: one for URLs and one for local files
    Channel
        .fromPath(params.gwas_csv)
        .splitCsv(header: true, strip: true)  // Strip whitespace
        .map { row ->
            def gwas = row.GWAS?.trim()
            def year = row.year?.trim()
            def source = row.path?.trim() ?: row.URL?.trim() // Support both 'path' and 'URL' for backward compatibility
            def genome_build = row.genome_build?.trim()
            
            // Validate genome_build
            if (!genome_build || !(genome_build in ['GRCh38', 'GRCh37'])) {
                error "Invalid or missing genome_build '${genome_build}' for GWAS '${gwas}'. Must be either 'GRCh38' or 'GRCh37'"
            }
            
            // Log what we're processing
            log.info "Processing row: GWAS=${gwas}, year=${year}, genome_build=${genome_build}, path=${source}"
            
            // Return a tuple with GWAS name, year, source, genome_build, and whether it's a local file
            [gwas, year, source, genome_build, (source ==~ /^\\/.*/ || source ==~ /^\\.\\/.*/ || source ==~ /^\\.\\.\\/.*/)]
        }
        .branch {
            local: it[4] == true    // Local file path
            remote: it[4] == false  // URL to download
        }
        .set { input_ch }
    
    // Create channels for download and stage processes
    download_ch = input_ch.remote.map { it[0..2] }  // Just keep gwas, year, url
    stage_ch = input_ch.local.map { it[0..2] }      // Just keep gwas, year, path
    
    // Process URLs through downloadGWAS
    downloadGWAS(download_ch)
    
    // Process local files through stageGWAS
    stageGWAS(stage_ch)
    
    // Merge the outputs from both processes for mungeGWAS
    gwas_files_ch = downloadGWAS.out.gwas_raw.mix(stageGWAS.out.gwas_raw)
    
    // Create a channel with genome_build information keyed by GWAS name
    genome_build_ch = input_ch.remote.mix(input_ch.local)
        .map { gwas, year, source, genome_build, is_local ->
            [gwas, genome_build]
        }
    
    // Join the channels to combine gwas files with their genome builds
    // gwas_files_ch emits: [meta, gwas_file] where meta = [gwas: gwas, year: year]
    // genome_build_ch emits: [gwas, genome_build]
    mungeGWAS_input = gwas_files_ch
        .map { meta, gwas_file -> [meta.gwas, meta, gwas_file] }  // Restructure to key by gwas name
        .join(genome_build_ch, by: 0)  // Join on gwas name
        .map { gwas, meta, gwas_file, genome_build -> [meta, gwas_file, genome_build] }  // Restructure for mungeGWAS
    
    // Process all files with mungeGWAS
    mungeGWAS(mungeGWAS_input)
}
