#' Convert chromosome:position format to rsID
#'
#' @param chromlocs Either a character vector of "chr:pos" strings or a data frame with 
#'                 CHR and BP columns
#' @param build Optional, specify genome build ("hg37"/"hg19" or "hg38"/"GRCh38"). 
#'              If NULL (default), will auto-detect based on best match.
#' @param autodetect_threshold Minimum success rate required to confirm a build (default: 0.5)
#' @param sample_size Number of positions to sample for autodetection (to improve speed)
#'
#' @return A list with: 
#'         - rsids: Vector of rsIDs or original inputs if no match found
#'         - build_used: The genome build detected or used
#'         - match_rate: Percentage of positions successfully mapped
#'
#' @examples
#' result <- chrpos_to_rsid(c("1:1000000", "2:2000000"))
#' result <- chrpos_to_rsid(data.frame(CHR=c(1,2), BP=c(1000000, 2000000)))
#'
chrpos_to_rsid <- function(chromlocs, build=NULL, 
                          autodetect_threshold=0.5,
                          sample_size=10000) {
  
  # Function to process data frame input
  process_df <- function(df) {
    # Ensure CHR and BP columns exist
    if(!all(c("CHR", "BP") %in% colnames(df))) {
      stop("Data frame must contain CHR and BP columns")
    }
    
    # Create a copy to avoid modifying the original
    df_copy <- data.frame(
      Chr = df$CHR,
      Pos = df$BP,
      stringsAsFactors = FALSE
    )
    
    # Clean chromosome format (remove "chr" prefix if present)
    if(length(grep("chr", df_copy$Chr)) > 0) {
      chronly <- strsplit(as.character(df_copy$Chr), "r")
      chronly <- as.data.frame(do.call(rbind, chronly))
      df_copy$Chr <- chronly$V2
    }
    
    return(df_copy)
  }
  
  # Function to process character vector input
  process_chr <- function(chr_vec) {
    original_names <- chr_vec
    chr_split <- strsplit(chr_vec, ":")
    chr_df <- as.data.frame(do.call(rbind, chr_split))
    
    # Handle cases where split resulted in more than 2 columns (e.g., URLs or paths)
    if(ncol(chr_df) > 2) {
      warning("Some inputs contain multiple ':' characters. Using first two parts only.")
      chr_df <- chr_df[, 1:2]
    } else if(ncol(chr_df) < 2) {
      stop("Input does not follow chr:pos format")
    }
    
    colnames(chr_df) <- c("Chr", "Pos")
    
    # Clean chromosome format (remove "chr" prefix if present)
    if(length(grep("chr", chr_df$Chr)) > 0) {
      chronly <- strsplit(as.character(chr_df$Chr), "r")
      chronly <- as.data.frame(do.call(rbind, chronly))
      chr_df$Chr <- chronly$V2
    }
    
    chr_df$original_names <- original_names
    return(chr_df)
  }
  
  # Main processing logic - determine input type and process accordingly
  if(is.data.frame(chromlocs)) {
    chromlocs_df <- process_df(chromlocs)
    input_type <- "dataframe"
    original_df <- chromlocs
  } else {
    chromlocs_df <- process_chr(chromlocs)
    input_type <- "vector"
    original_names <- chromlocs
  }
  
  # Create genomic ranges for lookup
  final <- data.frame(
    chrom = chromlocs_df$Chr,
    position = chromlocs_df$Pos,
    stringsAsFactors = FALSE
  )
  final <- final[order(final$chrom), ]
  final$paste <- paste0(final$chrom, ":", final$position)
  
  # Create genomic ranges object
  grSNPS <- GenomicRanges::makeGRangesFromDataFrame(final,
    seqnames.field = "chrom",
    start.field = "position",
    end.field = "position"
  )
  
  # If build is specified, use it directly
  if(!is.null(build)) {
    build <- tolower(build)
    if(build %in% c("hg19", "grch37")) build <- "hg37"
    if(build %in% c("grch38")) build <- "hg38"
    
    # Validate build input
    if(!build %in% c("hg37", "hg38")) {
      stop("Build must be 'hg37'/'hg19' or 'hg38'/'GRCh38'")
    }
    
    # Get SNP database for specified build
    if(build == "hg37") {
      snp <- SNPlocs.Hsapiens.dbSNP144.GRCh37::SNPlocs.Hsapiens.dbSNP144.GRCh37
    } else {
      check_version <- grep("155", system.file(package="SNPlocs.Hsapiens.dbSNP155.GRCh38"))
      if(length(check_version) == 1) {
        snp <- SNPlocs.Hsapiens.dbSNP155.GRCh38::SNPlocs.Hsapiens.dbSNP155.GRCh38
      } else {
        snp <- SNPlocs.Hsapiens.dbSNP151.GRCh38::SNPlocs.Hsapiens.dbSNP151.GRCh38
      }
    }
    
    rsids <- BSgenome::snpsByOverlaps(snp, grSNPS)
    rsids_df <- as.data.frame(rsids)
    rsids_df$paste <- paste0("chr", rsids_df$seqnames, ":", rsids_df$pos)
    chromlocs_df$paste <- paste0("chr", chromlocs_df$Chr, ":", chromlocs_df$Pos)
    
    match_idx <- match(chromlocs_df$paste, rsids_df$paste)
    chromlocs_df$rsid <- rsids_df$RefSNP_id[match_idx]
    
    # Calculate match rate
    match_rate <- sum(!is.na(chromlocs_df$rsid)) / nrow(chromlocs_df)
    
    # Use original names for non-matches
    if(input_type == "vector") {
      chromlocs_df$rsid <- dplyr::coalesce(chromlocs_df$rsid, chromlocs_df$original_names)
    }
    
    result <- list(
      rsids = chromlocs_df$rsid,
      build_used = build,
      match_rate = match_rate
    )
    
  } else {
    # Auto-detect build by trying both
    message("Auto-detecting genome build...")
    
    # Subsample positions if there are too many to speed up the detection
    sample_indices <- NULL
    if(nrow(chromlocs_df) > sample_size) {
      set.seed(42) # For reproducibility
      sample_indices <- sample(1:nrow(chromlocs_df), size=min(sample_size, nrow(chromlocs_df)))
      grSNPS_sample <- grSNPS[sample_indices]
    } else {
      grSNPS_sample <- grSNPS
    }
    
    # Try hg37 build
    message("Trying build hg37/GRCh37...")
    snp_hg37 <- SNPlocs.Hsapiens.dbSNP144.GRCh37::SNPlocs.Hsapiens.dbSNP144.GRCh37
    rsids_hg37 <- BSgenome::snpsByOverlaps(snp_hg37, grSNPS_sample)
    rsids_hg37_df <- as.data.frame(rsids_hg37)
    
    # Prepare for matching
    if(nrow(rsids_hg37_df) > 0) {
      rsids_hg37_df$paste <- paste0("chr", rsids_hg37_df$seqnames, ":", rsids_hg37_df$pos)
      
      # Get sample subset for comparison if needed
      if(!is.null(sample_indices)) {
        chromlocs_sample <- chromlocs_df[sample_indices, ]
      } else {
        chromlocs_sample <- chromlocs_df
      }
      
      chromlocs_sample$paste <- paste0("chr", chromlocs_sample$Chr, ":", chromlocs_sample$Pos)
      
      # Calculate match rate for hg37
      match_idx_hg37 <- match(chromlocs_sample$paste, rsids_hg37_df$paste)
      match_rate_hg37 <- sum(!is.na(match_idx_hg37)) / nrow(chromlocs_sample)
    } else {
      match_rate_hg37 <- 0
    }
    
    message(sprintf("hg37 match rate: %.2f%%", match_rate_hg37 * 100))
    
    # Try hg38 build
    message("Trying build hg38/GRCh38...")
    check_version <- grep("155", system.file(package="SNPlocs.Hsapiens.dbSNP155.GRCh38"))
    if(length(check_version) == 1) {
      snp_hg38 <- SNPlocs.Hsapiens.dbSNP155.GRCh38::SNPlocs.Hsapiens.dbSNP155.GRCh38
    } else {
      snp_hg38 <- SNPlocs.Hsapiens.dbSNP151.GRCh38::SNPlocs.Hsapiens.dbSNP151.GRCh38
    }
    
    rsids_hg38 <- BSgenome::snpsByOverlaps(snp_hg38, grSNPS_sample)
    rsids_hg38_df <- as.data.frame(rsids_hg38)
    
    # Prepare for matching
    if(nrow(rsids_hg38_df) > 0) {
      rsids_hg38_df$paste <- paste0("chr", rsids_hg38_df$seqnames, ":", rsids_hg38_df$pos)
      
      # Get sample subset for comparison if needed
      if(!is.null(sample_indices)) {
        chromlocs_sample <- chromlocs_df[sample_indices, ]
      } else {
        chromlocs_sample <- chromlocs_df
      }
      
      chromlocs_sample$paste <- paste0("chr", chromlocs_sample$Chr, ":", chromlocs_sample$Pos)
      
      # Calculate match rate for hg38
      match_idx_hg38 <- match(chromlocs_sample$paste, rsids_hg38_df$paste)
      match_rate_hg38 <- sum(!is.na(match_idx_hg38)) / nrow(chromlocs_sample)
    } else {
      match_rate_hg38 <- 0
    }
    
    message(sprintf("hg38 match rate: %.2f%%", match_rate_hg38 * 100))
    
    # Determine which build to use based on match rate
    if(max(match_rate_hg37, match_rate_hg38) < autodetect_threshold) {
      warning(paste0("Could not confidently detect genome build. ",
                    "Match rates: hg37=", round(match_rate_hg37*100, 2), "%, ",
                    "hg38=", round(match_rate_hg38*100, 2), "%. ",
                    "Using build with highest match rate."))
    }
    
    if(match_rate_hg37 >= match_rate_hg38) {
      build <- "hg37"
      message("Selected build hg37/GRCh37 based on higher match rate")
      
      # Process entire dataset with hg37
      rsids <- BSgenome::snpsByOverlaps(snp_hg37, grSNPS)
      rsids_df <- as.data.frame(rsids)
      match_rate <- match_rate_hg37
    } else {
      build <- "hg38"
      message("Selected build hg38/GRCh38 based on higher match rate")
      
      # Process entire dataset with hg38
      rsids <- BSgenome::snpsByOverlaps(snp_hg38, grSNPS)
      rsids_df <- as.data.frame(rsids)
      match_rate <- match_rate_hg38
    }
    
    # Apply rsIDs to full dataset
    if(nrow(rsids_df) > 0) {
      rsids_df$paste <- paste0("chr", rsids_df$seqnames, ":", rsids_df$pos)
      chromlocs_df$paste <- paste0("chr", chromlocs_df$Chr, ":", chromlocs_df$Pos)
      
      match_idx <- match(chromlocs_df$paste, rsids_df$paste)
      chromlocs_df$rsid <- rsids_df$RefSNP_id[match_idx]
    } else {
      chromlocs_df$rsid <- NA
    }
    
    # Use original names for non-matches
    if(input_type == "vector") {
      chromlocs_df$rsid <- dplyr::coalesce(chromlocs_df$rsid, chromlocs_df$original_names)
    }
    
    result <- list(
      rsids = chromlocs_df$rsid,
      build_used = build,
      match_rate = match_rate
    )
  }
  
  # Return result based on input type
  if(input_type == "dataframe") {
    # Add rsIDs back to the original dataframe
    original_df$rsid <- result$rsids
    result$data <- original_df
  }
  
  return(result)
}