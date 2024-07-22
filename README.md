# NuclearHorizontalTransfer

Code accompanying "Horizontal transfer of nuclear DNA in a transmissible cancer"

## Submodules
- `somatypus_nf`
    - Single nucleotide and small indel variant caller. Based on [Somatypus](https://github.com/baezortega/somatypus),
      but Nextflow-ified.
- `pb_genotyper`
    - PacBio variant genotyper.


## Misc
- `VAF_correction.R`
    - source this file in R to put the function `fast_estimate_tumour_vaf` in scope
