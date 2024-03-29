#' @title Make jive object
#' @description This function makes a jive object from a matrix of intraspecific observations
#' and species phylogeny. The obtained jive object can than be used as an input to \code{\link{jiveMCMC}} function
#' Intraspecific observations should be stored as matrix, where lines are vector of observations for each species,
#' with NA for no data. Phylogenetic tree can be either a simmap object (\code{\link{make.simmap}}) or phylo object (\code{\link{as.phylo}})
#' 
#' @details This function creates a jive object needed for \code{\link{jiveMCMC}} function.  
#' Trait values must be stored as a matrix, where lines are vectors of observations for each species, with NA for no data.
#' Rownames are species names. Phylogenetic tree must be provided as either simmap object (for models with multiple regimes)
#' or as a phylo object (for BM or OU1 models). Rownames and tip labels of a phylogenetic tree should match exactly. 
#' There are three models implemeted for estimation of species variances evolution - BM, OU1 and OUM. Evolution of 
#' species means is only implemented with BM model. Species-specific distribution are models as multivariate normal distribution
#' 
#' 
#' @param simmap an object of class "jive" (see details)
#' @param traits name of the output file that will store the log of MCMC chain
#' @param model.var sampling frequency of the MCMC chain (how often chain will be saved into output file
#' @param model.mean printing frequency of the MCMC chain (how often chain will be printed in the R console)					
#' @param model.lik number of classes for thermodynamic integration (see details)
#' @export
#' @author Anna Kostikova
#' @return An object of class jive
#' @examples
#' library(OUwie)
#' library(phytools)
#' library(MASS)
#' ## number of species we want to simulate
#' n <- 50
#' 
#' ## generate tree with a pure birth model and scale it to the height of 1
#' tree <- pbtree(b = 1, n = n, scale = 1, nsim = 1, ape = TRUE)
#' 
#' ## set parameters for OU1 model of species-specific variances
#' sig.sq <- 0.9
#' alpha  <- 0.1
#' theta0 <- 1
#' theta  <- 5
#' 
#' ## set parameters for BM model of specific-specific means
#' sig.sq.bm <- 0.5
#' mu0       <- 350
#' 
#' ## set mean number of observations per species
#' mean.obs <- 20
#' 
#' ## get selective regimes (all 1s because of OU1 model)
#' y <- data.frame(tree$tip.label, rep(1, n))
#' 
#' ## add node labels
#' tree$node.label <- rep("1", n-1)
#' 
#' ## simulate species-specific variances 
#' sigma.val <- abs(OUwie.sim(tree, y, simmap.tree=FALSE, 
#' scaleHeight=TRUE, alpha=rep(alpha,2),
#' sigma.sq=rep(sig.sq,2), theta0=theta0, theta=theta)$X)
#' 
#' ## simulate species-specific means
#' mean.val <- mvrnorm(mu=rep(mu0, length(tree$tip)), Sigma=(sig.sq.bm * vcv(tree)))
#' 
#' ## draw a random number of intraspecific observations for each species
#' spec.obs <- rpois(n, mean.obs)
#' 
#' ## generate a data matrix where rows are species and columns are individual observations	
#' traits <- matrix(rnorm(max(spec.obs) * n, mean=mean.val, sd=sqrt(sigma.val)), 
#' nrow=n, ncol=max(spec.obs))
#' traits <- cbind(as.matrix(max(spec.obs) - spec.obs), traits)
#' 
#' ## function to replace empty cells with NA
#' foo <- function(x){
#'		to <- x[1]
#'		x[1:(to + 1)] <- NA
#'		return(x[-1])
#' }
#' 
#' ## apply to data matrix	
#' traits <- as.matrix(t(apply(traits, 1, foo)))
#' 
#' ## add species names to rownames
#' rownames(traits) <- tree$tip.label
#' my.jive <- jiveMake(tree, traits,  model.var="OU1", model.mean="BM", model.lik="Multinorm")



jiveMake <- function(simmap, traits, model.var="OU1", model.mean="BM", model.lik="Multinorm"){

	jive <- list()
	
	if (name.check(simmap, traits) != "OK") {
	
		stop("Species do not match in tree and traits")
	
	} else {

		traits<-traits[simmap$tip.label,]
		
		if (model.var %in% c("BM", "OU1")) { # this is needed to overcome phytools limitation about making simmap obj from a trait with a single regime# td$phy$node.label <- rep("1", n - 1)
			jive$data$map <- matrix(rep(1, ((dim(traits)[1]) * 2) - 2))
		} else {
			jive$data$map <- relSim(simmap)$mapped.edge
		}
				
		jive$data$traits 					<- traits
		jive$data$counts 					<- apply(traits, 1, function (x) {sum( !is.na(x) )})
		jive$data$tree   					<- simmap
		jive$data$vcv    					<- vcv(simmap)
		jive$data$nreg   					<- dim(jive$data$map)[2]
		
		print(jive$data$nreg)
		
		
		if (model.lik == "Multinorm") {
			jive$lik$model 					<- likMultinorm
			jive$lik$mspws 					<- initWinSizeMVN(jive$data$traits)$msp
			jive$lik$sspws 					<- initWinSizeMVN(jive$data$traits)$ssp
			jive$lik$mspinit				<- initParamMVN(jive$data$traits)$mspA
			jive$lik$sspinit				<- initParamMVN(jive$data$traits)$sspA
				
		}
		
		if (model.mean == "BM" ) {
			jive$prior_mean$model 			<- likBM
			jive$prior_mean$init  			<- initParamMBM(jive$data$traits)  # check
			jive$prior_mean$ws	  			<- initWinSizeMBM(jive$data$traits)  # check
			jive$prior_mean$hprior$r		<- make.hpfun("Gamma", c(1.1,5))		  # sigma
			jive$prior_mean$hprior$m		<- make.hpfun("Uniform", c(-10000,10000)) # anc.mean

		
		}
		
		if (model.var == "BM" ) {
			jive$prior_var$model 			<- likBM
			jive$prior_var$init  			<- initParamVBM(jive$data$traits) # check
			jive$prior_var$ws	  			<- initWinSizeVBM(jive$data$traits) # check
			jive$prior_var$hprior$r			<- make.hpfun("Gamma", c(1.1,5)) # sigma
			jive$prior_var$hprior$m			<- make.hpfun("Gamma", c(1.1,5)) # anc.mean
			jive$prior_var$header			<- c("real.iter", "postA", "log.lik", "Prior_mean", "Prior_var",  "sumHpriorA", 
												"mbm_sig.sq", "mbm_anc.st",  "vbm_sig.sq", "vbm_anc.st", 
												paste(rownames(jive$data$traits), "_m", sep=""),
												paste(rownames(jive$data$traits), "_v", sep=""),
												"acc", "temperature")
	
		}

		
		if (model.var == "OU1" || model.var == "OUM") {
			jive$prior_var$model 			<- likOU
			jive$prior_var$init  			<- initParamVOU(jive$data$traits, jive$data$nreg)  # check
			jive$prior_var$ws	  			<- initWinSizeVOU(jive$data$traits, jive$data$nreg)  # check
			jive$prior_var$hprior$a			<- make.hpfun("Gamma", c(1.1,5)) # alpha
			jive$prior_var$hprior$r			<- make.hpfun("Gamma", c(1.1,5)) # sigma
			jive$prior_var$hprior$m			<- make.hpfun("Gamma", c(1.1,5)) # anc.mean
			for (i in 1:jive$data$nreg){									 # theta
				ti = paste("t",i,sep="")
				jive$prior_var$hprior[[ti]]	<- make.hpfun("Gamma", c(1.1,5))
			}
			jive$prior_var$header			<- c("real.iter", "postA", "log.lik", "Prior_mean", "Prior_var",  "sumHpriorA", 
												"mbm_sig.sq", "mbm_anc.st", "vou_alpha", "vou_sig.sq", "vou_anc.st", 
												paste("vou_theta", seq(1:jive$data$nreg),sep=""),
												paste(rownames(jive$data$traits), "_m", sep=""),
												paste(rownames(jive$data$traits), "_v", sep=""),
												"acc", "temperature")
		
		}
		
	}	
	return(jive)

}




