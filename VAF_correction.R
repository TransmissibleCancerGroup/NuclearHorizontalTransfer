#################
# Main function #
#################

# `fast_estimate_tumour_vaf` returns an estimate of the variant allele fraction
# in a pure tumour sample, from read counts observed in a host-contaminated
# sample.
# Also in this file: a few helper functions. These don't need to be called
# directly.

#' Fast approximate estimate of pure_tumour_vaf from a mixed sample
#' @param total_readdepth Tumour sample total read depth
#' @param alt_readdepth Tumour sample alt read depth
#' @param logr Tumour sample logR
#' @param host_total_readdepth Host sample total read depth
#' @param host_alt_readdepth Host sample alt read depth
#' @param purity Estimated purity of tumour sample
#' @param ploidy estimated ploidy of tumour sample
#' @param host_ploidy estimated ploidy of host sample (default = 2)
#' @export
fast_estimate_tumour_vaf <- function(total_readdepth, alt_readdepth, logr,
                                     host_total_readdepth, host_alt_readdepth,
                                     purity, ploidy, host_ploidy = 2) {
    result <- .estimate_contingency_table(total_readdepth, alt_readdepth, logr,
                                          host_total_readdepth,
                                          host_alt_readdepth,
                                          purity, ploidy, host_ploidy = 2)
    alt_reads <- alt_readdepth - result$L
    total_reads <- total_readdepth - result$K

    eps <- sqrt(.Machine$double.eps)
    alt_reads[abs(alt_reads) < eps] <- 0
    total_reads[abs(total_reads) < eps] <- 0

    vaf <- alt_reads / total_reads
    vaf[is.na(vaf)] <- 0
    pmax(0, pmin(1, vaf))
}

####################
# Helper functions #
####################

#' Fast deconvolution of read count contingency table. Used as basis of
#' the exported fast_estimate_* functions
#' @param total_readdepth Tumour sample total read depth
#' @param alt_readdepth Tumour sample alt read depth
#' @param logr Tumour sample logR
#' @param host_total_readdepth Host sample total read depth
#' @param host_alt_readdepth Host sample alt read depth
#' @param purity Estimated purity of tumour sample
.estimate_contingency_table <- function(total_readdepth,
                                        alt_readdepth,
                                        logr,
                                        host_total_readdepth,
                                        host_alt_readdepth,
                                        purity,
                                        ploidy,
                                        host_ploidy = 2) {
    # Aim: find values for the empty cells (a), (b), (c), (d), (e), (f)
    # in the read count contingency table below. A and T are observed values,
    # and R = T - A.
    # The other values need to be estimated, subject to the constraint that 
    # they are all non-negative.
    # (c) (referred to throughout as variable K) can be estimated as T*p_host,
    # where p_host is the probability that a read came from host material in
    # the mixed tumour-host source. p_host is estimated using the tumour
    # sample's logR (logr), and the host sample's VAF (hvaf).
    # (b) (variable L) is estimated from (c) as K*p_alt_given_host, where
    # p_alt_given_host is the probability that a host-derived read carries the
    # Alt allele, not the Ref allele. p_alt_given_host is equal to hvaf.
    # As the table has 2 degrees of freedom, once values are estimated for (b)
    # and (c), the other missing values are filled in trivially.

    # Contingency table :
    #'         |  Ref  |  Alt  |
    #'  -------|-------|-------|-------
    #'   Host  |  (a)  |  (b)  |  (c)
    #'  Tumour |  (d)  |  (e)  |  (f)
    #'  -------|-------|-------|-------
    #'         |   R   |   A   |   T

    hvaf <- host_alt_readdepth / host_total_readdepth
    hvaf[is.nan(hvaf)] <- 0
    T <- total_readdepth
    A <- alt_readdepth

    # probability that a read comes from the host (P(R=H))
    p_host <- prob_read_came_from_host(logr, purity, ploidy, host_ploidy)

    # probability that a host read is an Alt allele (P(R=A|R=H))
    p_alt_given_host <- hvaf

    # Estimate K (number of host reads) and L (number of host reads that are
    # Alt), subject to the constraints A - L >= 0, and (T - K) - (A - L) >= 0

    K <- T * p_host
    L <- K * p_alt_given_host

    # If constraints are broken, then find the optimal least squares solution
    # to the constrained equation, using Lagrangian multipliers.
    # Least-squares estimate for K and L:
    # f(K, L) = (K - T*p_host)^2 + (L - K*p_alt_given_host)
    #
    # Constraints:
    # g1(L, a) => A - L - a^2 = 0
    # g2(K, L, b) => (T-K) - (A-L) - b^2 = 0
    #
    # Augmented Lagrangian equation:
    # F(K, L, a, b, λ1, λ2) = f(K, L) + λ1*g1(L, a) + λ2*g2(K, L, b)
    #
    # Optimal constrained solution obtained when all derivatives of F are zero.

    # Broken constraint 1: Too many Alt reads in the host
    ix <- (L > A)

    K[ix] <- (A[ix] * p_alt_given_host[ix] + T[ix] * p_host[ix]) /
        (p_alt_given_host[ix]^2 + 1)
    L[ix] <- A[ix]

    # Broken constraint 2: VAF out of bounds [ignore if T==0 - these will give
    # NA in the index, which breaks]
    iy <- (T > 0) & ((((A - L) / (T - K)) > 1) |
                     (((A - L) / (T - K)) < 0) |
                     is.nan((A - L) / (T - K)))
    denom <- (p_alt_given_host[iy]^2 - 2 * p_alt_given_host[iy] + 2)
    K[iy] <- (A[iy] * (p_alt_given_host[iy] - 1) + T[iy] * (p_host[iy] - p_alt_given_host[iy] + 1)) / denom
    L[iy] <- (A[iy] * (p_alt_given_host[iy]^2 - p_alt_given_host[iy] + 1) + T[iy] * (p_host[iy] - p_alt_given_host[iy]^2 + p_alt_given_host[iy] - 1)) / denom

    # Contingency table :
    #'     |  Ref  |  Alt  |
    #'  ---|-------|-------|-------
    #'   H |  K-L  |   L   |   K
    #'   T |T-K-A+L|  A-L  |  T-K
    #'  ---|-------|-------|-------
    #'     |   R   |   A   |   T

    return(list(K=K, L=L))
}

#' Probability that a read came from the tumour
#' @param logr Tumour sample logR
#' @param purity Tumour sample purity
#' @param ploidy Tumour ploidy (ploidy of pure tumour)
#' @param host_ploidy Host ploidy estimate (almost always will be 2)
#' Derivation:
#' Expected proportion of tumour reads in a mixed sample, where Nt is
#' underlying tumour copy number state, Nh is host copy state, and p
#' is purity:
#'   P(read=Tumour) = p * Nt / (p * Nt + (1 - p) * Nh) (1)
#'
#' Tumour copynumber state is estimated as:
#'   Nt = (R * Nh * (p*ψt + (1-p) * ψh) - ψh * (1 - p) * Nh)
#'        --------------------------------------------------  (2)
#'                            p * ψh
#' Therefore,
#'  p * Nt = (R * Nh * (p*ψt + (1-p) * ψh) - ψh * (1 - p) * Nh)
#'           --------------------------------------------------  (3)
#'                             ψh
#' And,
#'  p * Nt + (1 - p) * Nh
#'         = (R * Nh * (p*ψt + (1-p) * ψh)
#'           -----------------------------   (4)
#'                       ψh
#' Substitute (3) and (4) into (1) to obtain the result.
prob_read_came_from_tumour <- function(logr, purity, ploidy, host_ploidy) {
    stopifnot(purity >= 0 & purity <= 1)
    stopifnot(ploidy > 0)
    stopifnot(host_ploidy > 0)
    denom <- 2^logr * (purity * ploidy + (1 - purity) * host_ploidy)
    p <- (denom - host_ploidy * (1 - purity)) / denom
    pmax(0, pmin(1, p))
}

#' Probability that a read came from the host. See `prob_read_came_from_tumour`
#' @param logr Tumour sample logR
#' @param purity Tumour sample purity
#' @param ploidy Tumour ploidy (ploidy of pure tumour)
#' @param host_copynumber Host copy number estimate (usually 2)
#' @param host_ploidy Host ploidy estimate (almost always will be 2)
prob_read_came_from_host <- function(logr, purity, ploidy, host_ploidy) {
    1 - prob_read_came_from_tumour(logr, purity, ploidy, host_ploidy)
}

