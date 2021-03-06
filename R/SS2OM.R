# === OM specification using SS3 (Methot 2012) stock assessments ====================

#' Reads MLE estimates from Stock Synthesis file structure into an operating model using package r4ss.
#'
#'
#' @description A function that uses the file location of a fitted SS3 model including input files to population the
#' various slots of an operating model with MLE parameter estimates. The function mainly populates the Stock and Fleet portions
#' of the operating model; the user still needs to parameterize most of the observation and implementation portions of the operating model.
#' @param SSdir A folder with Stock Synthesis input and output files in it
#' @param nsim The number of simulations to take for parameters with uncertainty (for OM@@cpars custom parameters).
#' @param proyears The number of projection years for MSE
#' @param reps The number of stochastic replicates within each simulation in the operating model.
#' @param maxF The maximum allowable F in the operating model.
#' @param seed The random seed for the operating model.
#' @param Obs The observation model (class Obs).
#' @param Imp The implementation model (class Imp).
#' @param Name The name of the operating model
#' @param Source Reference to assessment documentation e.g. a url
#' @param Author Who did the assessment
#' @param ... Arguments to pass to \link[r4ss]{SS_output}.
#' @note Currently supports the latest version of r4ss on CRAN (v.1.24). Function may be incompatible with newer versions of r4ss on Github.
#' @details Currently, the function uses values from the terminal year of the assessment for most life history parameters (growth, maturity, M, etc).
#' Steepness values for the operating model are obtained by bootstrapping from spawning biomass and recruitment estimates in the assessment.
#' @return An object of class OM.
#' @author T. Carruthers
#' @export
#' @seealso \link{SS2Data}
#' @importFrom stats acf
#' @importFrom r4ss SS_output
SS2OM <- function(SSdir, nsim = 48, proyears = 50, reps = 1, maxF = 3, seed = 1, Obs = DLMtool::Generic_Obs, Imp = DLMtool::Perfect_Imp,
                  Name = NULL, Source = "No source provided", Author = "No author provided", ...) {

  dots <- list(dir = SSdir, ...)
  if(!any(names(dots) == "covar")) dots$covar <- FALSE
  if(!any(names(dots) == "forecast")) dots$forecast <- FALSE
  if(!any(names(dots) == "ncols")) dots$ncols <- 1e3
  if(!any(names(dots) == "printstats")) dots$printstats <- FALSE
  if(!any(names(dots) == "verbose")) dots$verbose <- FALSE
  if(!any(names(dots) == "warn")) dots$warn <- FALSE

  message(paste("-- Using function SS_output of package r4ss version", packageVersion("r4ss"), "to extract data from SS file structure --"))
  message(paste("Reading directory:", SSdir))
  replist <- do.call(SS_output, dots)
  message("-- End of r4ss operations --")

  season_as_years <- FALSE
  if(replist$nseasons == 1 && replist$seasduration < 1) {
    message(paste("Season-as-years detected in SS model. There is one season in the year with duration of", replist$seasduration, "year."))
    season_as_years <- TRUE
    nseas <- 1/replist$seasduration
    message("DLMtool operating model is an annual model. Since the SS model is seasonal, we need to aggregate over seasons.")
  } else {
    nseas <- replist$nseasons
    if(nseas > 1) {
      message("DLMtool operating model is an annual model. Since the SS model is seasonal, we need to aggregate over seasons.")
    }
  }

  # Create OM object
  Stock <- new("Stock")
  Fleet <- new("Fleet")
  OM <- new("OM", Stock = Stock, Fleet = Fleet, Obs = Obs, Imp = Imp)
  OM@nsim <- nsim
  OM@proyears <- proyears
  if(is.null(Name)) {
    OM@Name <- SSdir
  } else {
    OM@Name <- Name
  }
  OM@Source <- paste0(Source,". Author: ", Author, ".")

  mainyrs <- replist$startyr:replist$endyr
  OM@nyears <- nyears <- ceiling(length(mainyrs) / ifelse(season_as_years, nseas, 1))

  seas1_yind_full <- expand.grid(nseas = 1:nseas, nyears = 1:nyears)
  seas1_yind <- which(seas1_yind_full$nseas == 1)

  OM@maxF <- maxF
  OM@reps <- reps
  OM@seed <- seed

  # === Stock parameters =========================================================================================================

  # Growth --------------------------------------
  growdat <- getGpars(replist)      # Age-specific parameters in endyr

  # Max age
  OM@maxage <- maxage <- ceiling(nrow(growdat)/ifelse(season_as_years, nseas, 1))

  seas1_aind_full <- expand.grid(nseas = 1:nseas, age = 1:maxage)
  seas1_aind <- which(seas1_aind_full$nseas == 1)

  # Length and weight
  Len_age <- growdat$Len_Mid
  if(season_as_years) Len_age <- Len_age[seas1_aind]
  #Len_at_age <- array(Len_age, dim = c(maxage, nyears + proyears, nsim))
  #Len_at_age <- aperm(Len_at_age, c(3, 1, 2))
  Len_age2 <- array(NA, dim = c(maxage, nsim, nyears+proyears))
  Len_age2[, , 1:nyears] <- Len_age
  Len_age2[, , nyears + 1:proyears] <- Len_age2[, , nyears]
  OM@cpars$Len_age <- aperm(Len_age2, c(2, 1, 3)) # dims = nsim, max_age, nyears+proyears

  GP <- replist$Growth_Parameters   # Some growth parameters (presumably in endyr)
  if(nrow(GP)>1){
    message(paste(nrow(GP),"different rows of growth parameters were reported by r4ss:"))
    print(GP)
    message("Only the first row of values will be used.\n")
  }

  muLinf <- GP$Linf[1]
  cvLinf <- GP$CVmax[1]
  if(cvLinf > 1) cvLinf <- cvLinf/muLinf
  t0 <- GP$A_a_L0[1]
  t0[t0 > 1] <- 0
  muK <- GP$K[1]
  if(muK <= 0) { #Estimate K from Len_age if K < 0 (e.g., age-varying K with negative deviations in K).
    get_K <- function(K, Lens, Linf, t0, ages) sum((Lens - (Linf * (1 - exp(-K * (ages - t0)))))^2)
    muK <- optimize(get_K, c(0, 2), Lens = Len_age, Linf = muLinf, t0 = t0, ages = 1:maxage)$minimum
  }
  out <- negcorlogspace(muLinf, muK, cvLinf, nsim) # K and Linf negatively correlated 90% with identical CV to Linf
  Linf <- out[ ,1]
  K <- out[ ,2]

  OM@Linf <- quantile(Linf, c(0.025, 0.975))
  OM@K <- quantile(K, c(0.025, 0.975))
  OM@t0 <- rep(GP$A_a_L0[1], 2)

  OM@LenCV <- rep(cvLinf, 2)
  OM@Ksd <- OM@Kgrad <- OM@Linfsd <- OM@Linfgrad <- c(0, 0)

  # Depletion --------------------------------------
  OM@D <- rep(replist$current_depletion, 2)

  # Weight at age
  Wt_age <- growdat$Wt_Mid
  if(season_as_years) Wt_age <- Wt_age[seas1_aind]
  Wt_age2 <- array(NA, dim = c(maxage, nsim, nyears+proyears))
  Wt_age2[, , 1:nyears] <- Wt_age * rep(trlnorm(nsim, 1, cvLinf), each = maxage)
  Wt_age2[, , nyears + 1:proyears] <- Wt_age2[, , nyears]
  OM@cpars$Wt_age <- aperm(Wt_age2, c(2, 1, 3)) # dims = nsim, max_age, nyears+proyears

  # Maturity --------------------------------------
  if(min(growdat$Len_Mat < 1)) {                    # Condition to check for length-based maturity
    Mat <- growdat$Len_Mat/max(growdat$Len_Mat)
  } else {                                          # Use age-based maturity
    Mat <- growdat$Age_Mat/max(growdat$Age_Mat)
  }
  if(season_as_years) Mat <- Mat[seas1_aind]

  # Currently using linear interpolation of mat vs len, is robust and very close to true logistic model predictions
  L50 <- LinInterp(Mat, Len_age, 0.5+1e-6)
  OM@L50 <- rep(L50, 2)

  L95 <- LinInterp(Mat, Len_age, 0.95)
  OM@L50_95 <- rep(L95-L50, 2)

  OM@a <- GP$WtLen1[1]
  OM@b <- GP$WtLen2[1]

  # M --------------------------------------
  M <- growdat$M
  if(season_as_years) M <- M[seas1_aind]

  OM@M <- M
  OM@M2 <- M + 1e-5
  OM@Mexp <- OM@Msd <- OM@Mgrad <- c(0, 0)  # No time-varying M

  # Stock-recruit relationship --------------------------------------
  SR_ind <- match(mainyrs, replist$recruit$year)
  SSB <- replist$recruit$spawn_bio[SR_ind]
  rec <- replist$recruit$pred_recr[SR_ind]

  #res <- try(SSB0 <- as.numeric(replist$Dynamic_Bzero$SPB[replist$Dynamic_Bzero$Era == "VIRG"]), silent = TRUE)
  res <- try(SSB0 <- replist$derived_quants[replist$derived_quants$LABEL == "SPB_Virgin", 2], silent = TRUE)
  if(inherits(res, "try-error")) SSB0 <- SSB[1]

  res2 <- try(R0 <- replist$derived_quants[replist$derived_quants$LABEL == "Recr_Virgin", 2], silent = TRUE)
  if(inherits(res, "try-error")) {
    surv <- c(1, exp(-cumsum(M[1:(maxage-1)])))
    SpR0 <- sum(Wt_age * Mat * surv)
    R0 <- SSB0/SpR0
  } else {
    SpR0 <- SSB0/(R0 * ifelse(season_as_years, nseas, 1))
  }

  # In season as year model, R0 is the seasonal rate of recruitment, must adjust for annual model
  OM@R0 <- R0 * ifelse(season_as_years, nseas, 1)

  # Steepness
  if(replist$SRRtype == 3 || replist$SRRtype == 6) { # Beverton-Holt SR
    SR <- "BH"
    OM@SRrel <- 1L
    steep <- replist$parameters[grepl("steep", rownames(replist$parameters)), ]

    set.seed(42)

    hs <- rnorm(nsim, steep$Value, ifelse(is.na(steep$Parm_StDev), 0, steep$Parm_StDev))
    hs[hs < 0.2] <- 0.2
    hs[hs > 0.99] <- 0.99
  } else if(replist$SRRtype == 2) {
    SR <- "Ricker"
    OM@SRrel <- 2L
    steep <- replist$parameters[grepl("SR_Ricker", rownames(replist$parameters)), ]

    set.seed(42)

    hs <- rnorm(nsim, steep$Value, ifelse(is.na(steep$Parm_StDev), 0, steep$Parm_StDev))
    hs[hs < 0.2] <- 0.2
  } else {
    message("Steepness value not found. Estimating steepness by re-sampling R and SSB estimates from assessment.")
    hs <- SRopt(nsim, SSB, rec, SpR0, plot = FALSE, type = SR)
  }

  OM@cpars$hs <- hs
  OM@h <- quantile(hs, c(0.025, 0.975))

  # Recruitment deviations --------------------------------------

  if(season_as_years) {
    # Boundary rec devs (in nyear = 1)
    first_year <- mainyrs[1] - (maxage - 1) * nseas
    rec_ind <- first_year:(mainyrs[1]-1)
    rec_ind <- match(rec_ind, replist$recruit$year)
    recs_boundary <- aggregate(replist$recruit$dev[rec_ind], list(rep(1:(maxage-1), each = nseas)), mean, na.rm = TRUE)$x

    # Nyears rec dev (main)
    rec_ind <- 1:nrow(seas1_yind_full) + mainyrs[1] - 1
    rec_ind <- match(rec_ind, replist$recruit$year)
    recs <- aggregate(replist$recruit$dev[rec_ind], list(seas1_yind_full$nyears), mean, na.rm = TRUE)$x
    recs <- c(recs_boundary, recs)
    recs[is.nan(recs)] <- 0
  } else {
    year_first_rec_dev <- mainyrs[1] - maxage + 1
    rec_ind <- match(year_first_rec_dev:replist$endyr, replist$recruit$year)
    recs <- rep(0, maxage + nyears - 1)
    recs <- replist$recruit$dev[rec_ind]
    recs[is.na(recs)] <- 0
  }

  if(all(recs == 0)) {
    AC <- 0
  } else {
    AC <- acf(recs[recs != 0], plot = FALSE)$acf[2, 1, 1]
    if(is.na(AC)) AC <- 0
  }

  procsd <- replist$sigma_R_in
  procmu <- -0.5 * procsd^2 # adjusted log normal mean
  Perr_hist <- matrix(rep(recs, each = nsim), nrow = nsim) # Historical recruitment is deterministic
  Perr_proj <- matrix(rnorm(proyears * nsim, rep(procmu, each = nsim),
                            rep(procsd, each = nsim)), nrow = nsim) # Sample recruitment for projection

  if(AC != 0) {
    for(y in 1:ncol(Perr_proj)) { # Add autocorrelation to projection recruitment
      if(y == 1) {
        Perr_proj[, y] <- AC * Perr_hist[, ncol(Perr_hist)] + Perr_proj[, y] * sqrt(1 - AC^2)
      } else {
        Perr_proj[, y] <- AC * Perr_proj[, y-1] + Perr_proj[, y] * sqrt(1 - AC^2)
      }
    }
  }

  Perr_y <- cbind(Perr_hist, Perr_proj)

  OM@cpars$Perr_y <- exp(Perr_y)
  OM@Perr <- rep(procsd, 2) # uniform range is a point estimate from assessment MLE
  OM@AC <- rep(AC, 2)

  # Movement modelling ----------------------------
  OM@Frac_area_1 <- OM@Size_area_1 <- OM@Prob_staying <- rep(0.5, 2)
  if(nrow(replist$movement) > 0){
    movement <- replist$movement[replist$movement$Seas == 1 & replist$movement$Gpattern == 1, ]
    nareas <- length(unique(movement$Source_area))

    full_movement <- movement[, grepl("age", names(movement)) & names(movement) != "minage" & names(movement) != "maxage"]
    nages <- ncol(full_movement)
    mov <- array(NA, c(nsim, nages, nareas, nareas))

    for(i in 1:nrow(full_movement)) {
      from <- movement$Source_area[i]
      to <- movement$Dest_area[i]

      for(j in 1:ncol(full_movement)) mov[1:nsim, j, from, to] <- full_movement[i, j]
    }
    mov[is.na(mov)] <- 0

    if(season_as_years) mov <- mov[, seas1_aind, , , drop = FALSE]

    OM@cpars$mov <- mov
  }

  # Fleet parameters ============================================================================================================

  # Vulnerability --------------------------------------------
  ages <- growdat$Age
  cols <- match(ages, names(replist$Z_at_age))
  rows <- match(mainyrs, replist$Z_at_age$Year)

  Z_at_age <- replist$Z_at_age[rows, ]
  M_at_age <- replist$M_at_age[rows, ]

  rows2 <- Z_at_age$Gender == 1 & Z_at_age$Bio_Pattern == 1
  F_at_age <- t(Z_at_age[rows2, cols] - M_at_age[rows2, cols])
  F_at_age[nrow(F_at_age), ] <- F_at_age[nrow(F_at_age) - 1, ] # assume F at maxage = F at maxage-1

  if(ncol(F_at_age) < nyears) { # Typically because forecast is off
    F_at_age_terminal <- F_at_age[, ncol(F_at_age)]
    F_at_age <- cbind(F_at_age, F_at_age_terminal)
  }
  if(ncol(F_at_age) == nyears && all(is.na(F_at_age[, ncol(F_at_age)]))) {
    F_at_age[, ncol(F_at_age)] <- F_at_age[, ncol(F_at_age)-1]
  }

  F_at_age[F_at_age < 1e-8] <- 1e-8

  if(season_as_years) {
    Ftab <- expand.grid(Age = 1:dim(F_at_age)[1], Yr = 1:dim(F_at_age)[2])
    Ftab$F_at_age <- as.vector(F_at_age)

    # Mean F across aggregated age (groups of nseas), then sum F across aggregated years (groups of nseas)
    sumF <- aggregate(Ftab[, 3], list(Age = seas1_aind_full[1:nrow(F_at_age), 2][Ftab[, 1]], Yr = Ftab[, 2]), mean, na.rm = TRUE)
    sumF <- aggregate(sumF[, 3], list(Age = sumF[, 1], Yr = rep(seas1_yind_full[1:ncol(F_at_age), 2], each = maxage)), sum, na.rm = TRUE)

    F_at_age <- matrix(sumF[, 3], nrow = maxage)
  }

  V <- array(NA, dim = c(maxage, nyears + proyears, nsim))
  V[, 1:nyears, ] <- array(F_at_age[, 1:nyears], dim = c(maxage, nyears, nsim))
  V[, nyears:(nyears+proyears), ] <- V[, nyears, ]
  V <- aperm(V, c(3, 1, 2))
  Find <- apply(V, c(1, 3), max, na.rm = TRUE) # get apical F

  for(i in 1:nsim) {
    for(j in 1:(nyears + proyears)) {
      V[i, , j] <- V[i, , j]/Find[i, j]
    }
  }

  OM@cpars$V <- V

  # These are not used if V is in cpars, however will be used by observational model.
  muFage <- apply(F_at_age, 1, mean)
  Vuln <- muFage/max(muFage, na.rm = TRUE)
  L5 <- LinInterp(Vuln, Len_age, 0.05, ascending = TRUE, zeroint = TRUE)
  Vmaxlen <- Vuln[length(Vuln)]
  LFS <- Len_age[which.min((exp(Vuln)-exp(1.05))^2 * 1:length(Vuln))]
  OM@L5 <- rep(L5, 2)
  OM@LFS <- rep(LFS, 2)
  OM@Vmaxlen<-rep(Vmaxlen, 2)

  OM@isRel <- "FALSE" # these are real lengths not relative to length at 50% maturity

  # -- Fishing mortality rate index ----------------------------
  OM@cpars$Find <- Find[, 1:nyears] # is only historical years

  OM@Spat_targ <- rep(1, 2) # What if it's a multiple-area SS model?

  Fpos <- Find[, 1:(nyears-1)]
  Fpos <- Fpos[, apply(Fpos,2,sum) > 0]
  Fpos[Fpos == 0] <- 1e-5
  ind1 <- 1:(ncol(Fpos)-1)
  ind2 <- 2:ncol(Fpos)
  Esd <- apply((Fpos[, ind1] - Fpos[, ind2])/Fpos[,ind2], 1, sd)
  OM@Esd <- quantile(Esd, c(0.025, 0.975))
  OM@EffYears <- 1:nyears
  OM@EffLower <- OM@EffUpper <- Find[1, 1:nyears]
  OM@qinc <- c(0, 0)
  OM@qcv <- OM@Esd

  OM@Period <- OM@Amplitude <- rep(NaN, 2)

  OM@CurrentYr <- ifelse(season_as_years, nyears, replist$endyr)

  # Observation model parameters ==============================================================================

  # Index observations -------------------------------------------------------
  OM@Iobs <- rep(sd(log(replist$cpue$Obs)-log(replist$cpue$Exp), na.rm = TRUE), 2)
  getbeta<-function(beta,x,y) sum((y - x^beta)^2, na.rm = TRUE)
  OM@beta<-rep(optimize(getbeta,x=replist$cpue$Obs,y=replist$cpue$Exp,interval=c(0.1,10))$minimum,2)

  return(OM)
}



#' Linear interpolation of a y value at level xlev based on a vector x and y
#'
#' @param x A vector of x values
#' @param y A vector of y values (identical length to x)
#' @param xlev A the target level of x from which to guess y
#' @param ascending Are the the x values supposed to be ordered before interpolation
#' @param zeroint is there a zero-zero x-y intercept?
#' @author T. Carruthers
#' @export LinInterp
LinInterp<-function(x,y,xlev,ascending=FALSE,zeroint=FALSE){

  if(zeroint){
    x<-c(0,x)
    y<-c(0,y)
  }

  if(ascending){
    cond<-(1:length(x))<which.max(x)
  }else{
    cond<-rep(TRUE,length(x))
  }

  close<-which.min((x[cond]-xlev)^2)

  ind<-c(close,close+(x[close]<xlev)*2-1)
  ind <- ind[ind <= length(x)]
  if (length(ind)==1) ind <- c(ind, ind-1)
  if (min(ind)==0) ind <- 1:2
  ind<-ind[order(ind)]

  pos<-(xlev-x[ind[1]])/(x[ind[2]]-x[ind[1]])
  max(1,y[ind[1]]+pos*(y[ind[2]]-y[ind[1]]))

}



#' A function that samples multivariate normal (logspace) variables
#'
#' @param xmu The mean (normal space) of the first (x) variable
#' @param ymu The mean (normal space) of the second (y) variable
#' @param xcv The coefficient of variation (normal space, log normal sd) of the x variable
#' @param nsim The number of random draws
#' @param cor The off-diagonal (symmetrical) correlation among x and y
#' @param ploty Whether a plot of the sampled variables should be produced
#' @author T. Carruthers
#' @export negcorlogspace
#' @importFrom mvtnorm rmvnorm
negcorlogspace<-function(xmu,ymu,xcv=0.1,nsim,cor=-0.9,ploty=FALSE){

  varcov=matrix(c(1,cor,cor,1),nrow=2)
  out<-mvtnorm::rmvnorm(nsim,c(0,0),sigma=varcov)
  out<-out/rep(apply(out,2,sd)/xcv,each=nsim)
  out<-exp(out)
  out<-out/rep(apply(out,2,mean),each=nsim)
  out[,1]<-out[,1]*xmu
  out[,2]<-out[,2]*ymu
  if(ploty)plot(out[,1],out[,2])
  out

}

#' Simplified a multi-area transition matrix into the best 2 x 2 representation
#'
#' @description A Function that takes a larger movement matrix, identifies the most parsimonious representation of 2 non-mixed areas and returns the final unfished movement matrix
#' @param movtab a table of estimated movements
#' @author T. Carruthers
#' @export getGpars
movdistil<-function(movtab){

  nareas<-max(movtab$Source_area,movtab$Dest_area)
  mov<-array(0,c(nareas,nareas))
  mov[cbind(movtab$Source_area,movtab$Dest_area)]<-movtab[,ncol(movtab)]

  vec<-rep(1/nareas,nareas)
  for(i in 1:100)vec<-vec%*%mov
  endmov<-array(vec,c(nareas,nareas))*mov

  listy<-new('list')
  for(i in 1:nareas)listy[[i]]<-c(1,2)

  combins<-expand.grid(listy)
  combins<-combins[!apply(combins,1,sum)%in%c(nareas*1,nareas*2),]
  nc<-nrow(combins)/2
  combins<-combins[(nc+1):nrow(combins),]

  base<-cbind(expand.grid(1:nareas,1:nareas),as.vector(endmov))

  emt<-NULL
  out<-rep(NA,nc)

  for(i in 1:nc){

    vec<-combins[i,]
    vec<-c(-1,1)[as.numeric(vec)]
    out[i]<-sum((vec-(vec%*%mov))^2)

  }

  best<-as.numeric(combins[which.min(out),])

  aggdat<-cbind(expand.grid(best,best),as.vector(endmov))
  agg<-aggregate(aggdat[,3],by=list(aggdat[,1],aggdat[,2]),sum)
  newmov<-array(NA,c(2,2))
  newmov[as.matrix(agg[,1:2])]<-agg[,3]
  newmov/apply(newmov,1,sum)

}

#' Predict recruitment and return fit to S-R observations
#'
#' @description Internal function to \link{optSR}
#' @param pars an initial guess at model parameters steepness and R0
#' @param SSB 'observations' of spawning biomass
#' @param rec 'observations' (model predictions) of recruitment
#' @param SSBpR spawning stock biomass per recruit at unfished conditions
#' @param mode should fit (= 1) or recruitment deviations (not 1) be returned
#' @param plot should a plot of the model fit be produced?#'
#' @param type what type of stock recruitment curve is being fitted ("BH" = Beverton-Holt or "Ricker")
#' @author T. Carruthers
#' @export
getSR <- function(pars, SSB, rec, SSBpR, mode = 1, plot = FALSE, type = c("BH", "Ricker")){
  R0 <- exp(pars[2])
  if(type == "BH") {
    h <- 0.2 + 0.8 * ilogit(pars[1])
    recpred<-((0.8*R0*h*SSB)/(0.2*SSBpR*R0*(1-h)+(h-0.2)*SSB))
  }
  if(type == "Ricker") {
    h <- 0.2 + exp(pars[1])
    recpred <- SSB * (1/SSBpR) * (5*h)^(1.25*(1 - SSB/(R0*SSBpR)))
  }

  if(plot){
    ord <- order(SSB)
    plot(SSB[ord], rec[ord], ylim=c(0, max(rec, R0)), xlim=c(0, max(SSB, R0*SSBpR)), xlab="", ylab="")
    SSB2 <- seq(0, R0*SSBpR, length.out=500)
    if(type == "BH") recpred2 <- ((0.8*R0*h*SSB2)/(0.2*SSBpR*R0*(1-h)+(h-0.2)*SSB2))
    if(type == "Ricker") recpred2 <- SSB2 * (1/SSBpR) * (5*h)^(1.25*(1 - SSB2/(R0*SSBpR)))
    lines(SSB2, recpred2, col='blue')
    abline(v=c(0.2*R0*SSBpR, R0*SSBpR), lty=2, col='red')
    abline(h=c(R0, R0*h), lty=2, col='red')
    legend('topright', legend=c(paste0("h = ", round(h,3)), paste0("ln(R0) = ", round(log(R0),3))), bty='n')
  }

  if(mode==1){
    #return(sum(((recpred-rec)/10000)^2))
    sigmaR <- sqrt(sum((log(rec/recpred))^2)/length(recpred))
    return(-sum(dnorm(log(rec)-log(recpred),0,sigmaR,log=T)))
    #-dnorm(pars[1],0,6,log=T)) # add a vague prior on h = 0.6
    #return(-sum(dnorm(recpred,rec,rec*0.5,log=T)))
  }else{
    return(rec-recpred)
  }
}

#' Wrapper for estimating stock recruitment parameters from resampled stock-recruitment data
#'
#' @param x position to accommodate lapply-type functions
#' @param SSB 'observations' of spawning biomass
#' @param rec 'observations' (model predictions) of recruitment
#' @param SSBpR spawning stock biomass per recruit at unfished conditions
#' @param pars an initial guess at model parameters steepness and R0
#' @param frac the fraction of observations for resampling
#' @param plot should a plot of model fit be produced?
#' @param type what type of stock recruitment curve is being fitted ("BH" = Beverton-Holt or "Ricker")
#' @return Estimated value of steepness.
#' @author T. Carruthers
#' @export
optSR<-function(x, SSB, rec, SSBpR, pars, frac = 0.5, plot = FALSE, type = c("BH", "Ricker")) {
  type <- match.arg(type)
  samp <- sample(1:length(SSB), size = ceiling(length(SSB) * frac), replace = FALSE)
  opt <- optim(pars, getSR, method = "BFGS", #lower = c(-6, pars[2]/50), upper = c(6, pars[2] * 50),
               SSB = SSB[samp], rec = rec[samp], SSBpR = SSBpR, mode = 1, plot = FALSE, type = type)
  if(plot) getSR(opt$par, SSB, rec, SSBpR, mode = 2, plot = plot, type = type)
  if(type == "BH") h <- 0.2 + 0.8 * ilogit(opt$par[1])
  if(type == "Ricker") h <- 0.2 + exp(opt$par[1])
  return(h)
}

#' Function that returns a stochastic estimate of steepness given observed stock recruitment data
#'
#' @param nsim number of samples of steepness to generate
#' @param SSB 'observations' of spawning biomass
#' @param rec 'observations' (model predictions) of recruitment
#' @param SSBpR spawning stock biomass per recruit at unfished conditions
#' @param plot should plots of model fit be produced?
#' @param type what type of stock recruitment curve is being fitted ("BH" = Beverton-Holt or "Ricker")
#' @return Vector of length nsim with steepness values.
#' @author T. Carruthers
#' @export
SRopt <- function(nsim, SSB, rec, SSBpR, plot = FALSE, type = c("BH", "Ricker")) {
  type <- match.arg(type)
  R0temp <- rec[1] # have a guess at R0 for initializing nlm
  pars <- c(0, log(R0temp))
  #SSBpR=SSB[1]/rec[1]
  vapply(1:nsim, optSR, numeric(1), SSB = SSB, rec = rec, SSBpR = SSBpR, pars = pars, frac = 0.8,
         plot = plot, type = type)
}


#' Extracts growth parameters from a SS3 r4ss replist
#'
#' @param replist the list output of the r4ss SS_output function (a list of assessment inputs / outputs)
#' @param seas The reference season for the growth (not actually sure what this does yet)
#' @author T. Carruthers
#' @export getGpars
getGpars<-function(replist, seas = 1) { # This is a rip-off of SSPlotBiology

  nseasons <- replist$nseasons
  growdat <- replist$endgrowth[replist$endgrowth$Seas == seas, ]
  growdat$CV_Beg <- growdat$SD_Beg/growdat$Len_Beg
  growthCVtype <- replist$growthCVtype
  biology <- replist$biology
  startyr <- replist$startyr
  FecType <- replist$FecType
  FecPar1name <- replist$FecPar1name
  FecPar2name <- replist$FecPar2name
  FecPar1 <- replist$FecPar1
  FecPar2 <- replist$FecPar2
  parameters <- replist$parameters
  nsexes <- replist$nsexes
  mainmorphs <- replist$mainmorphs
  accuage <- replist$accuage
  startyr <- replist$startyr
  endyr <- replist$endyr
  growthvaries <- replist$growthvaries
  growthseries <- replist$growthseries
  ageselex <- replist$ageselex
  MGparmAdj <- replist$MGparmAdj
  wtatage <- replist$wtatage
  Growth_Parameters <- replist$Growth_Parameters
  Grow_std <- replist$derived_quants[grep("Grow_std_", replist$derived_quants$LABEL), ]
  if (nrow(Grow_std) == 0) {
    Grow_std <- NULL
  }  else {
    Grow_std$pattern <- NA
    Grow_std$sex_char <- NA
    Grow_std$sex <- NA
    Grow_std$age <- NA
    for (irow in 1:nrow(Grow_std)) {
      tmp <- strsplit(Grow_std$LABEL[irow], split = "_")[[1]]
      Grow_std$pattern[irow] <- as.numeric(tmp[3])
      Grow_std$sex_char[irow] <- tmp[4]
      Grow_std$age[irow] <- as.numeric(tmp[6])
    }
    Grow_std$sex[Grow_std$sex_char == "Fem"] <- 1
    Grow_std$sex[Grow_std$sex_char == "Mal"] <- 2
  }
  if (!is.null(replist$wtatage_switch)) {
    wtatage_switch <- replist$wtatage_switch
  } else{ stop("SSplotBiology function doesn't match SS_output function. Update one or both functions.")
  }
  if (wtatage_switch)
    cat("Note: this model uses the empirical weight-at-age input.\n",
        "     Therefore many of the parametric biology quantities which are plotted\n",
        "     are not used in the model.\n")
  if (!seas %in% 1:nseasons)
    stop("'seas' input should be within 1:nseasons")

  if (length(mainmorphs) > nsexes) {
    cat("!Error with morph indexing in SSplotBiology function.\n",
        " Code is not set up to handle multiple growth patterns or birth seasons.\n")
  }
  if (FecType == 1) {
    fec_ylab <- "Eggs per kg"
    FecX <- biology$Wt_len_F
    FecY <- FecPar1 + FecPar2 * FecX
  }

  growdatF <- growdat[growdat$Gender == 1 & growdat$Morph ==
                        mainmorphs[1], ]
  growdatF$Sd_Size <- growdatF$SD_Beg

  if (growthCVtype == "logSD=f(A)") {
    growdatF$high <- qlnorm(0.975, meanlog = log(growdatF$Len_Beg),
                            sdlog = growdatF$Sd_Size)
    growdatF$low <- qlnorm(0.025, meanlog = log(growdatF$Len_Beg),
                           sdlog = growdatF$Sd_Size)
  }  else {
    growdatF$high <- qnorm(0.975, mean = growdatF$Len_Beg,
                           sd = growdatF$Sd_Size)
    growdatF$low <- qnorm(0.025, mean = growdatF$Len_Beg,
                          sd = growdatF$Sd_Size)
  }
  if (nsexes > 1) {
    growdatM <- growdat[growdat$Gender == 2 & growdat$Morph ==
                          mainmorphs[2], ]
    xm <- growdatM$Age_Beg
    growdatM$Sd_Size <- growdatM$SD_Beg
    if (growthCVtype == "logSD=f(A)") {
      growdatM$high <- qlnorm(0.975, meanlog = log(growdatM$Len_Beg),
                              sdlog = growdatM$Sd_Size)
      growdatM$low <- qlnorm(0.025, meanlog = log(growdatM$Len_Beg),
                             sdlog = growdatM$Sd_Size)
    }    else {
      growdatM$high <- qnorm(0.975, mean = growdatM$Len_Beg,
                             sd = growdatM$Sd_Size)
      growdatM$low <- qnorm(0.025, mean = growdatM$Len_Beg,
                            sd = growdatM$Sd_Size)
    }
  }

  growdatF

}



someplot<-function (replist, yrs = "all", Ftgt = NA, ylab = "Summary Fishing Mortality",
          plot = TRUE, print = FALSE, plotdir = "default", verbose = TRUE,
          uncertainty = TRUE, pwidth = 6.5, pheight = 5, punits = "in",
          res = 300, ptsize = 10)
{
  pngfun <- function(file, caption = NA) {
    png(filename = file, width = pwidth, height = pheight,
        units = punits, res = res, pointsize = ptsize)
    plotinfo <- rbind(plotinfo, data.frame(file = file, caption = caption))
    return(plotinfo)
  }
  plotinfo <- NULL
  if (plotdir == "default")
    plotdir <- replist$inputs$dir
  if (yrs[1] == "all") {
    yrs <- replist$startyr:replist$endyr
  }
  Ftot <- replist$derived_quants[match(paste("F_", yrs, sep = ""),
                                       replist$derived_quants$LABEL), ]
  if (all(is.na(Ftot$Value))) {
    warning("Skipping SSplotSummaryF because no real values found in DERIVED_QUANTITIES\n",
            "    Values with labels like F_2012 may not be real.\n")
    return()
  }
  Fmax <- max(c(Ftot$Value, Ftgt + 0.01), na.rm = TRUE)
  if (uncertainty) {
    uppFtot <- Ftot$Value + 1.96 * Ftot$StdDev
    lowFtot <- Ftot$Value - 1.96 * Ftot$StdDev
    Fmax <- max(c(uppFtot, Ftgt + 0.01), na.rm = TRUE)
  }
  plotfun <- function() {
    plot(0, type = "n", , xlab = "Year", ylab = ylab, xlim = range(yrs),
         ylim = c(0, Fmax), cex.lab = 1, cex.axis = 1, cex = 0.7)
    abline(h = 0, col = "grey")
    if (uncertainty)
      segments(as.numeric(substring(Ftot$LABEL, 3, 6)),
               uppFtot, as.numeric(substring(Ftot$LABEL, 3,
                                             6)), lowFtot, col = gray(0.5))
    points(as.numeric(substring(Ftot$LABEL, 3, 6)), Ftot$Value,
           pch = 16, type = "p")
    abline(h = Ftgt, col = "red")
  }
  if (plot)
    plotfun()
  if (print) {
    file <- file.path(plotdir, "ts_summaryF.png")
    caption <- "Summary F (definition of F depends on setting in starter.ss)"
    plotinfo <- pngfun(file = file, caption = caption)
    plotfun()
    dev.off()
    if (!is.null(plotinfo))
      plotinfo$category <- "Timeseries"
  }
  if (verbose)
    cat("Plotting Summary F\n")
  return(invisible(plotinfo))
}


