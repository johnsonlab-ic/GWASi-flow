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
    publishDir "${params.outdir}/processed", mode: 'copy'
    
    
    input:
    tuple val(meta), path(gwas_file)
    val genome_build // Default genome build, can be parameterized if needed
    
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
    tempFile <- "temp_${meta.gwas}_normalized.txt"
    outputFile <- paste0("${meta.gwas}_processed", genome_build, ".txt")
    
    # Check if the file has headers to convert
    cat("Checking file headers for standardization...\n")
    
    # Read first few lines to check headers (efficient for large files)
    fileHeader <- fread(inputFile, nrows = 1)
    columnNames <- names(fileHeader)
    
    # Print original column names
    cat("Original column names:", paste(columnNames, collapse = ", "), "\n")
    
    # Check for problematic column names
    needsConversion <- any(columnNames %in% c("chromosome", "base_pair_position", "base_pair_location"))
    
    if (needsConversion) {
        cat("Found non-standard column names. Converting to MungeSumstats format...\n")
        
        # Read the data, potentially large so use fread
        sumstatsData <- fread(inputFile)
        
        # Rename columns
        if ("chromosome" %in% columnNames) {
            cat("Converting 'chromosome' to 'CHR'\\n")
            setnames(sumstatsData, "chromosome", "CHR")
        }
        
        if ("base_pair_position" %in% columnNames) {
            cat("Converting 'base_pair_position' to 'BP'\\n")
            setnames(sumstatsData, "base_pair_position", "BP")
        }
        
        if ("base_pair_location" %in% columnNames) {
            cat("Converting 'base_pair_location' to 'POS'\\n")
            setnames(sumstatsData, "base_pair_location", "BP")
        }

        if ("SNP_ID" %in% columnNames) {
            cat("Converting 'SNP_ID' to 'SNP'\\n")
            setnames(sumstatsData, "SNP_ID", "SNP")
        }
        
        if ("other_allele" %in% columnNames) {
            cat("Converting 'other_allele' to 'REF'\\n")
            setnames(sumstatsData, "other_allele", "REF")
        }

        if ("effect_allele" %in% columnNames) {
            cat("Converting 'effect_allele' to 'ALT'\\n")
            setnames(sumstatsData, "effect_allele", "ALT")
        }


        
        # Write the modified data
        fwrite(sumstatsData, tempFile, sep = "\\t")
        cat("Finished converting column names. Using preprocessed file for MungeSumstats.\n")
        
        # Use the temp file for MungeSumstats
        inputFile <- tempFile
    }
    
    # Process with MungeSumstats
    cat("Processing with MungeSumstats...\n")
    MungeSumstats::format_sumstats(
        inputFile,
        save_path = outputFile,
        impute_beta = TRUE,
        impute_se = TRUE,
        ignore_multi_trait=TRUE
    )
    
    # Clean up temp file if it was created
    if (needsConversion && file.exists(tempFile)) {
        file.remove(tempFile)
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
            
            // Log what we're processing
            log.info "Processing row: GWAS=${gwas}, year=${year}, path=${source}"
            
            // Return a tuple with GWAS name, year, source, and whether it's a local file
            [gwas, year, source, (source ==~ /^\\/.*/ || source ==~ /^\\.\\/.*/ || source ==~ /^\\.\\.\\/.*/)]
        }
        .branch {
            local: it[3] == true    // Local file path
            remote: it[3] == false  // URL to download
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
    
    // Process all files with mungeGWAS
    mungeGWAS(gwas_files_ch, params.genome_build)
}
