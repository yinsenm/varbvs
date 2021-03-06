# This script fits two variable selection models: the first ("null") model
# has a uniform prior for all variables (the 442,001 genetic markers), and
# the second model has higher prior probability for genetic markers near
# cytokine signaling genes. This analysis assess support for enrichment of
# Crohn's disease risk factors near cytokine signaling genes; a large Bayes
# factor means greater support for the enrichment hypothesis. The data in
# this analysis consist of 442,001 SNPs genotyped for 1,748 cases and 2,938
# controls.
#
# Note that file cd.RData cannot be made publicly available due to
# data sharing restrictions, so this script is for viewing only.
#
library(varbvs)
library(lattice)

# Initialize the random number generator. 
set.seed(1)

# LOAD GENOTYPES, PHENOTYPES AND PATHWAY ANNOTATION
# -------------------------------------------------
cat("LOADING DATA.\n")
load("cd.RData")
data(cytokine)

# FIT VARIATIONAL APPROXIMATION
# -----------------------------
# Compute the variational approximation given the assumption that all
# variables (genetic markers) are, *a priori*, equally likely to be included
# in the model.
cat("FITTING NULL MODEL TO DATA.\n")
fit.null <- varbvs(X,NULL,y,"binomial",logodds = -4)

# Compute the variational approximation given the assumption that
# genetic markers near cytokine signaling genes are more likely to be
# included in the model.
cat("FITTING PATHWAY ENRICHMENT MODEL TO DATA.\n")
logodds <- matrix(-4,442001,13)
logodds[cytokine == 1,] <- matrix(-4 + seq(0,3,0.25),6711,13,byrow = TRUE)
fit.cytokine <- varbvs(X,NULL,y,"binomial",logodds = logodds,
                       alpha = fit.null$alpha,mu = fit.null$mu,
                       eta = fit.null$eta,optimize.eta = TRUE)

# Compute the Bayes factor.
BF <- bayesfactor(fit.null$logw,fit.cytokine$logw)

# SAVE RESULTS
# ------------
cat("SAVING RESULTS.\n")
save(list = c("fit.null","fit.cytokine","map","cytokine","BF"),
     file = "varbvs.demo.cytokine.RData")

# Show two "genome-wide scans" from the multi-marker PIPs, with and
# without conditioning on enrichment of cytokine signaling genes.
trellis.device(height = 4,width = 10)
w <- normalizelogweights(fit.cytokine$logw)
i <- which(fit.null$alpha > 0.5 | fit.cytokine$alpha %*% w > 0.5)
var.labels <- paste0(round(map$pos[i]/1e6,digits = 2),"Mb")
print(plot(fit.null,groups = map$chr,vars = i,var.labels = NULL,
           gap = 7500,ylab = "posterior prob."),
      split = c(1,1,1,2),more = TRUE)
print(plot(fit.cytokine,groups = map$chr,vars = i,var.labels = var.labels,
           gap = 7500,ylab = "posterior prob."),
      split = c(1,2,1,2),more = FALSE)
