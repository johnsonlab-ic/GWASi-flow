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
    
    # More robust file type detection and decompression
    FILE_TYPE=$(file -b downloaded_file)
    echo "File type detected: $FILE_TYPE"
    
    if [[ "$FILE_TYPE" == *"gzip"* || "$url" == *.gz || "$url" == *.gzip ]]; then
        echo "Detected gzip file, decompressing..."
        gzip -cd downloaded_file > "${gwas}_raw.txt"
    elif [[ "$FILE_TYPE" == *"Zip"* || "$FILE_TYPE" == *"zip"* || "$url" == *.zip ]]; then
        echo "Detected zip file, extracting..."
        unzip -p downloaded_file > "${gwas}_raw.txt"
    elif [[ "$FILE_TYPE" == *"bzip2"* || "$url" == *.bz2 || "$url" == *.bzip2 ]]; then
        echo "Detected bzip2 file, decompressing..."
        bzip2 -cd downloaded_file > "${gwas}_raw.txt"
    else
        echo "Assuming uncompressed file, copying directly..."
        cp downloaded_file "${gwas}_raw.txt"
    fi
    
    # Verify the file was correctly decompressed
    echo "Checking output file format:"
    file "${gwas}_raw.txt"
    """
}

// Process 2: Stage local GWAS file (runs locally without container)
process stageGWAS {
    label "process_single"
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
    FILE_TYPE=$(file -b "${local_file}")
    echo "File type detected: $FILE_TYPE"
    
    if [[ "$FILE_TYPE" == *"gzip"* || "${local_file}" == *.gz || "${local_file}" == *.gzip ]]; then
        echo "Detected gzip file, decompressing..."
        gzip -cd "${local_file}" > "${gwas}_raw.txt"
    elif [[ "$FILE_TYPE" == *"Zip"* || "$FILE_TYPE" == *"zip"* || "${local_file}" == *.zip ]]; then
        echo "Detected zip file, extracting..."
        unzip -p "${local_file}" > "${gwas}_raw.txt"
    elif [[ "$FILE_TYPE" == *"bzip2"* || "${local_file}" == *.bz2 || "${local_file}" == *.bzip2 ]]; then
        echo "Detected bzip2 file, decompressing..."
        bzip2 -cd "${local_file}" > "${gwas}_raw.txt"
    else
        echo "Assuming uncompressed file, copying directly..."
        cp "${local_file}" "${gwas}_raw.txt"
    fi
    
    # Verify the file was correctly decompressed
    echo "Checking output file format:"
    file "${gwas}_raw.txt"
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
    // Read CSV file and split into two channels: one for URLs and one for local files
    Channel
        .fromPath(params.gwas_csv)
        .splitCsv(header: true, strip: true)  // Strip whitespace
        .map { row ->
            def gwas = row.GWAS?.trim()
            def year = row.year?.trim()
            def source = row.URL?.trim()
            
            // Log what we're processing
            log.info "Processing row: GWAS=${gwas}, year=${year}, source=${source}"
            
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
