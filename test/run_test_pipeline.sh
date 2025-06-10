#!/bin/bash
# Test script to verify the pipeline with the improved chrpos_to_rsid function

# Set up test directory
TEST_DIR="test_run_$(date +%Y%m%d_%H%M%S)"
mkdir -p $TEST_DIR

# Create a test CSV file with both URL and local file
cat > $TEST_DIR/test_gwas.csv << EOF
GWAS,year,path
GWAS_URL,2020,https://raw.githubusercontent.com/neurogenomics/MungeSumstats/master/inst/extdata/eduAttainOkbay.txt
EOF

# Run the pipeline with the test data
cd $TEST_DIR
nextflow run ../main.nf \
  --gwas_csv test_gwas.csv \
  --outdir results \
  --genome_build auto \
  -with-docker

# Check results
echo ""
echo "Test complete. Check results in $TEST_DIR/results"
echo "Build detection report: $TEST_DIR/results/reports/genome_build_summary.txt"
