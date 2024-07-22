# NuclearHorizontalTransfer

Code accompanying "Horizontal transfer of nuclear DNA in a transmissible cancer"

## Submodules
- `somatypus_nf`
    - Single nucleotide and small indel variant caller. Based on [Somatypus](https://github.com/baezortega/somatypus),
      but Nextflow-ified.
- `pb_genotyper`
    - PacBio variant genotyper.
- `snv_analysis_pipeline`
    - Postprocessing of Somatypus output - separates germline and somatic variants,
    does quality filtering, runs Variant Effect Predictor, builds phylogenetic trees.
- `cnpipe`
    - An R package containing various helper functions for working with copy number data.
- `copynumber_calling_pipeline`
    - Custom copy number variant calling pipeline. Requires `cnpipe`.
- `nf_population_genetics`
    - Nextflow pipeline for population genetics analysis.

## Misc
- `VAF_correction.R`
    - source this file in R to put the function `fast_estimate_tumour_vaf` in scope
    - this function is available separately through `cnpipe`
