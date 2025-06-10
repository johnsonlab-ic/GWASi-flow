#!/usr/bin/env Rscript

# Test script for the enhanced chrpos_to_rsid function
# Run with: Rscript test_chrpos_to_rsid.R

# Load the function
source("../R/chrpos_to_rsid.r")

# Test with vector input
cat("Testing with vector input (auto-detect build)...\n")
test_vector <- c("1:1000000", "2:2000000", "3:3000000", "4:4000000", "5:5000000")
result1 <- chrpos_to_rsid(test_vector)
cat("Detected build:", result1$build_used, "\n")
cat("Match rate:", result1$match_rate, "\n")
print(head(result1$rsids))

# Test with dataframe input
cat("\nTesting with dataframe input (auto-detect build)...\n")
test_df <- data.frame(
  CHR = c(1, 2, 3, 4, 5), 
  BP = c(1000000, 2000000, 3000000, 4000000, 5000000)
)
result2 <- chrpos_to_rsid(test_df)
cat("Detected build:", result2$build_used, "\n")
cat("Match rate:", result2$match_rate, "\n")
print(head(result2$rsids))

# Test with specific build
cat("\nTesting with specified build (hg38)...\n")
result3 <- chrpos_to_rsid(test_vector, build="hg38")
cat("Used build:", result3$build_used, "\n")
cat("Match rate:", result3$match_rate, "\n")
print(head(result3$rsids))

# Test with mixed genome builds to see if detection works
cat("\nTesting with mixed positions from different builds...\n")
# These positions should have better mapping in hg38
hg38_positions <- c("1:1234567", "2:2345678", "3:3456789")
# These positions should have better mapping in hg37
hg37_positions <- c("1:9876543", "2:8765432", "3:7654321")
mixed_positions <- c(hg38_positions, hg37_positions)

result4 <- chrpos_to_rsid(mixed_positions)
cat("Detected build with mixed input:", result4$build_used, "\n")
cat("Match rate:", result4$match_rate, "\n")
print(head(result4$rsids))

cat("\nTest completed!\n")
