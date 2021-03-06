#' Surplus production model with UMSY and MSY as leading parameters
#'
#' A surplus production model that estimates the TAC using a
#' time-series of catches and a relative abundance index and coded in TMB.
#' The model is conditioned on catch and estimates a predicted index. The state-space version
#' estimates annual deviates in biomass.
#'
#' @param x An index for the objects in \code{Data} when running in closed loop simulation.
#' Otherwise, equals to 1 When running an assessment interactively.
#' @param Data An object of class Data.
#' @param rescale A multiplicative factor that rescales the catch in the assessment model, which
#' can improve convergence. By default, \code{"mean1"} scales the catch so that time series mean is 1, otherwise a numeric.
#' Output is re-converted back to original units.
#' @param start Optional list of starting values. See details.
#' @param fix_dep Logical, whether to fix the initial depletion (ratio of biomass to carrying capacity in the
#' first year of the model). If \code{TRUE}, uses the value in \code{start}, otherwise equal to 1
#' (assumes virgin conditions).
#' @param fix_n Logical, whether to fix the exponent of the production function. If \code{TRUE},
#' uses the value in \code{start}, otherwise equal to \code{n = 2}, where the biomass at MSY
#' is half of carrying capacity.
#' @param fix_sigma Logical, whether the standard deviation of the index is fixed. If \code{TRUE},
#' sigma is fixed to value provided in \code{start} (if provided), otherwise, value based on \code{Data@@CV_Ind}.
#' @param fix_tau Logical, the standard deviation of the biomass deviations is fixed. If \code{TRUE},
#' tau is fixed to value provided in \code{start} (if provided), otherwise, equal to 1.
#' @param early_dev Character string describing the years for which biomass deviations are estimated in \code{SP_SS}.
#' By default, deviations are estimated in each year of the model (\code{"all"}), while deviations could also be estimated
#' once index data are available (\code{"index"}).
#' @param integrate Logical, whether the likelihood of the model integrates over the likelihood
#' of the biomass deviations (thus, treating it as a state-space variable).
#' @param silent Logical, passed to \code{\link[TMB]{MakeADFun}}, whether TMB
#' will print trace information during optimization. Used for dignostics for model convergence.
#' @param opt_hess Logical, whether the hessian function will be passed to \code{\link[stats]{nlminb}} during optimization
#' (this generally reduces the number of iterations to convergence, but is memory and time intensive and does not guarantee an increase
#' in convergence rate). Ignored if \code{integrate = TRUE}.
#' @param n_restart The number of restarts (calls to \code{\link[stats]{nlminb}}) in the optimization procedure, so long as the model
#' hasn't converged. The optimization continues from the parameters from the previous (re)start.
#' @param control A named list of parameters regarding optimization to be passed to
#' \code{\link[stats]{nlminb}}.
#' @param inner.control A named list of arguments for optimization of the random effects, which
#' is passed on to \link[TMB]{newton} via \code{\link[TMB]{MakeADFun}}.
#' @param ... Additional arguments (not currently used).
#' @details
#' To provide starting values for the \code{SP}, a named list can be provided for \code{UMSY},
#' \code{MSY}, \code{dep}, and \code{n} via the start argument (see example).
#'
#' For \code{SP_SS}, a start value can also be provided for \code{sigma} and \code{tau}, the standard deviation
#' of the index and log-biomass deviates, respectively. Deviations are estimated beginning in the year when index
#' data are available.
#' @return An object of \code{\linkS4class{Assessment}} containing objects and output
#' from TMB.
#' @note The model uses the Fletcher (1978) formulation and is parameterized with UMSY and MSY as
#' leading parameters. The default conditions assume virgin conditions in the first year of the time series
#' and a symmetric production function.
#' @author Q. Huynh
#' @references
#' Fletcher, R. I. 1978. On the restructuring of the Pella-Tomlinson system.
#' Fishery Bulletin 76:515:521.
#'
#' Pella, J. J. and Tomlinson, P. K. 1969. A generalized stock production model.
#' Inter-Am. Trop. Tuna Comm., Bull. 13:419-496.
#' @section Required Data:
#' \itemize{
#' \item \code{SP}: Cat, Ind
#' \item \code{SP_SS}: Cat, Ind
#' }
#' @section Optional Data:
#' \code{SP_SS}: CV_Ind
#' @export SP
#' @seealso \link{SP_production}
#' @describeIn SP Fixed effects model
#' @examples
#' \donttest{
#' data(swordfish)
#'
#' #### Observation-error surplus production model
#' res <- SP(Data = swordfish)
#'
#' # Provide starting values, assume B/K = 0.95 in first year of model
#' # and symmetrical production curve (n = 2)
#' start <- list(UMSY = 0.1, MSY = 1e5, dep = 0.95, n = 2)
#' res <- SP(Data = swordfish, start = start)
#'
#' #### State-space version
#' res <- SP_SS(Data = swordfish, start = list(dep = 0.95, tau = 0.3),
#' fix_sigma = TRUE)
#' }
#' @seealso \link{plot,Assessment,ANY-method} \link{summary,Assessment-method} \link{retrospective} \link{profile_likelihood} \link{make_MP}
#' @import TMB
#' @importFrom stats nlminb
#' @useDynLib MSEtool
SP <- function(x = 1, Data, rescale = "mean1", start = NULL, fix_dep = TRUE, fix_n = TRUE,
               silent = TRUE, opt_hess = FALSE, n_restart = ifelse(opt_hess, 0, 1),
               control = list(iter.max = 5e3, eval.max = 1e4), ...) {
  dependencies = "Data@Cat, Data@Ind"
  dots <- list(...)
  if(any(names(dots) == "yind")) {
    yind <- eval(dots$yind)
  } else {
    ystart <- which(!is.na(Data@Cat[x, ]))[1]
    yind <- ystart:length(Data@Cat[x, ])
  }
  Year <- Data@Year[yind]
  C_hist <- Data@Cat[x, yind]
  if(any(is.na(C_hist))) stop('Model is conditioned on complete catch time series, but there is missing catch.')
  I_hist <- Data@Ind[x, yind]
  I_hist[I_hist < 0] <- NA
  ny <- length(C_hist)

  if(rescale == "mean1") rescale <- 1/mean(C_hist)
  data <- list(model = "SP", C_hist = C_hist * rescale, I_hist = I_hist, ny = ny)

  params <- list()
  if(!is.null(start)) {
    if(!is.null(start$UMSY) && is.numeric(start$UMSY)) params$logit_UMSY <- logit(start$UMSY[1])
    if(!is.null(start$MSY) && is.numeric(start$MSY)) params$log_MSY <- log(start$MSY[1])
    if(!is.null(start$dep) && is.numeric(start$dep)) params$log_dep <- log(start$dep[1])
    if(!is.null(start$n) && is.numeric(start$n)) params$log_n <- log(start$n[1])
  }
  if(is.null(params$logit_UMSY)) {
    UMSY_start <- ifelse(is.na(Data@Mort[x]), 0.2, 1 - exp(-0.5 * Data@Mort[x]))
    params$logit_UMSY <- logit(UMSY_start)
  }
  if(is.null(params$log_MSY)) {
    AvC <- mean(C_hist * rescale)
    params$log_MSY <- log(3 * AvC)
  }
  if(is.null(params$log_dep)) params$log_dep <- log(1)
  if(is.null(params$log_n)) params$log_n <- log(2)

  info <- list(Year = Year, data = data, params = params, rescale = rescale, control = control)

  map <- list()
  if(fix_dep) map$log_dep <- factor(NA)
  if(fix_n) map$log_n = factor(NA)
  obj <- MakeADFun(data = info$data, parameters = info$params, hessian = TRUE,
                   map = map, DLL = "MSEtool", silent = silent)
  mod <- optimize_TMB_model(obj, control, opt_hess, n_restart)
  opt <- mod[[1]]
  SD <- mod[[2]]
  report <- obj$report(obj$env$last.par.best)

  if(rescale != 1) {
    vars_div <- c("B", "BMSY", "SP", "K", "MSY")
    vars_mult <- NULL
    var_trans <- c("MSY", "K", "q")
    fun_trans <- c("/", "/", "*")
    fun_fixed <- c("log", NA, NA)
    rescale_report(vars_div, vars_mult, var_trans, fun_trans, fun_fixed)
  }

  Yearplusone <- c(Year, max(Year) + 1)

  nll_report <- ifelse(is.character(opt), report$nll, opt$objective)
  Assessment <- new("Assessment", Model = "SP", Name = Data@Name, conv = !is.character(SD) && SD$pdHess,
                    UMSY = report$UMSY, MSY = report$MSY, BMSY = report$BMSY, VBMSY = report$BMSY,
                    B0 = report$K, VB0 = report$K, U = structure(report$U, names = Year),
                    U_UMSY = structure(report$U/report$UMSY, names = Year),
                    B = structure(report$B, names = Yearplusone),
                    B_BMSY = structure(report$B/report$BMSY, names = Yearplusone),
                    B_B0 = structure(report$B/report$K, names = Yearplusone),
                    VB = structure(report$B, names = Yearplusone),
                    VB_VBMSY = structure(report$B/report$BMSY, names = Yearplusone),
                    VB_VB0 = structure(report$B/report$K, names = Yearplusone),
                    Obs_Catch = structure(C_hist, names = Year),
                    Obs_Index = structure(I_hist, names = Year),
                    Index = structure(report$Ipred, names = Year),
                    NLL = structure(c(nll_report, report$nll - report$penalty, report$penalty),
                                    names = c("Total", "Index", "Penalty")),
                    info = info, obj = obj, opt = opt, SD = SD, TMB_report = report,
                    dependencies = dependencies)

  if(Assessment@conv) {
    Assessment@SE_UMSY <- SD$sd[names(SD$value) == "UMSY"]
    Assessment@SE_MSY <- SD$sd[names(SD$value) == "MSY"]
    Assessment@SE_U_UMSY_final <- SD$sd[names(SD$value) == "U_UMSY_final"]
    Assessment@SE_B_BMSY_final <- SD$sd[names(SD$value) == "B_BMSY_final"]
    Assessment@SE_B_B0_final <- SD$sd[names(SD$value) == "B_K_final"]
    Assessment@SE_VB_VBMSY_final <- SD$sd[names(SD$value) == "B_BMSY_final"]
    Assessment@SE_VB_VB0_final <- SD$sd[names(SD$value) == "B_K_final"]
  }
  return(Assessment)
}
class(SP) <- "Assess"


#' @describeIn SP State-space version
#' @export SP_SS
#' @import TMB
#' @importFrom stats nlminb
#' @useDynLib MSEtool
SP_SS <- function(x = 1, Data, rescale = "mean1", start = NULL, fix_dep = TRUE, fix_n = TRUE, fix_sigma = TRUE,
                  fix_tau = TRUE, early_dev = c("all", "index"), integrate = FALSE, silent = TRUE,
                  opt_hess = FALSE, n_restart = ifelse(opt_hess, 0, 1),
                  control = list(iter.max = 5e3, eval.max = 1e4), inner.control = list(), ...) {
  dependencies = "Data@Cat, Data@Ind, Data@CV_Ind"
  dots <- list(...)
  early_dev <- match.arg(early_dev)
  if(any(names(dots) == "yind")) {
    yind <- eval(dots$yind)
  } else {
    ystart <- which(!is.na(Data@Cat[x, ]))[1]
    yind <- ystart:length(Data@Cat[x, ])
  }
  Year <- Data@Year[yind]
  C_hist <- Data@Cat[x, yind]
  if(any(is.na(C_hist))) stop('Model is conditioned on complete catch time series, but there is missing catch.')
  I_hist <- Data@Ind[x, yind]
  I_hist[I_hist < 0] <- NA
  ny <- length(C_hist)

  if(rescale == "mean1") rescale <- 1/mean(C_hist)
  if(early_dev == "all") est_B_dev <- rep(1, ny)
  if(early_dev == "index") {
    est_B_dev <- ifelse(c(1:ny) < which(is.na(I_hist))[1], NA, 1)
  }
  data <- list(model = "SP_SS", C_hist = C_hist * rescale, I_hist = I_hist, ny = ny,
               est_B_dev = est_B_dev)

  params <- list()
  if(!is.null(start)) {
    if(!is.null(start$UMSY) && is.numeric(start$UMSY)) params$logit_UMSY <- logit(start$UMSY[1])
    if(!is.null(start$MSY) && is.numeric(start$MSY)) params$log_MSY <- log(start$MSY[1])
    if(!is.null(start$dep) && is.numeric(start$dep)) params$log_dep <- log(start$dep[1])
    if(!is.null(start$n) && is.numeric(start$n)) params$log_n <- log(start$n[1])
    if(!is.null(start$sigma) && is.numeric(start$sigma)) params$log_sigma <- log(start$sigma[1])
    if(!is.null(start$tau) && is.numeric(start$tau)) params$log_tau <- log(start$tau[1])
  }
  if(is.null(params$logit_UMSY)) {
    UMSY_start <- ifelse(is.na(Data@Mort[x]), 0.2, 1 - exp(-0.5 * Data@Mort[x]))
    params$logit_UMSY <- logit(UMSY_start)
  }
  if(is.null(params$log_MSY)) {
    AvC <- mean(C_hist * rescale)
    params$log_MSY <- log(3 * AvC)
  }
  if(is.null(params$log_dep)) params$log_dep <- log(1)
  if(is.null(params$log_n)) params$log_n <- log(2)
  if(is.null(params$log_sigma)) {
    sigmaI <- max(0.05, sdconv(1, Data@CV_Ind[x]), na.rm = TRUE)
    params$log_sigma <- log(sigmaI)
  }
  if(is.null(params$log_tau)) params$log_tau <- log(0.3)
  params$log_B_dev = rep(0, ny)

  map <- list()
  if(fix_dep) map$log_dep <- factor(NA)
  if(fix_n) map$log_n = factor(NA)
  if(fix_sigma) map$log_sigma <- factor(NA)
  if(fix_tau) map$log_tau <- factor(NA)
  if(any(is.na(est_B_dev))) {
    nest <- sum(!is.na(est_B_dev))
    map_log_B_dev <- est_B_dev
    map_log_B_dev[!is.na(est_B_dev)] <- 1:nest
    map$log_B_dev <- factor(map_log_B_dev)
  }

  random <- NULL
  if(integrate) random <- "log_B_dev"

  info <- list(Year = Year, data = data, params = params, rescale = rescale, control = control,
               inner.control = inner.control)
  obj <- MakeADFun(data = info$data, parameters = info$params, hessian = TRUE,
                   map = map, random = random, DLL = "MSEtool", silent = silent)
  mod <- optimize_TMB_model(obj, control, opt_hess, n_restart)
  opt <- mod[[1]]
  SD <- mod[[2]]
  report <- obj$report(obj$env$last.par.best)

  if(rescale != 1) {
    vars_div <- c("B", "BMSY", "SP", "K", "MSY")
    vars_mult <- NULL
    var_trans <- c("MSY", "K", "q")
    fun_trans <- c("/", "/", "*")
    fun_fixed <- c("log", NA, NA)
    rescale_report(vars_div, vars_mult, var_trans, fun_trans, fun_fixed)
  }

  Yearplusone <- c(Year, max(Year) + 1)

  nll_report <- ifelse(is.character(opt), ifelse(integrate, NA, report$nll), opt$objective)
  Assessment <- new("Assessment", Model = "SP_SS", Name = Data@Name, conv = !is.character(SD) && SD$pdHess,
                    UMSY = report$UMSY, MSY = report$MSY, BMSY = report$BMSY, VBMSY = report$BMSY,
                    B0 = report$K, VB0 = report$K, U = structure(report$U, names = Year),
                    U_UMSY = structure(report$U/report$UMSY, names = Year),
                    B = structure(report$B, names = Yearplusone),
                    B_BMSY = structure(report$B/report$BMSY, names = Yearplusone),
                    B_B0 = structure(report$B/report$K, names = Yearplusone),
                    VB = structure(report$B, names = Yearplusone),
                    VB_VBMSY = structure(report$B/report$BMSY, names = Yearplusone),
                    VB_VB0 = structure(report$B/report$K, names = Yearplusone),
                    Obs_Catch = structure(C_hist, names = Year),
                    Obs_Index = structure(I_hist, names = Year),
                    Index = structure(report$Ipred, names = Year),
                    Dev = structure(report$log_B_dev, names = Year),
                    Dev_type = "log-Biomass deviations",
                    NLL = structure(c(nll_report, report$nll_comp, report$penalty),
                                    names = c("Total", "Index", "Dev", "Penalty")),
                    info = info, obj = obj, opt = opt, SD = SD, TMB_report = report,
                    dependencies = dependencies)

  if(Assessment@conv) {
    if(integrate) {
      SE_Dev <- sqrt(SD$diag.cov.random)
    } else {
      SE_Dev <- sqrt(diag(SD$cov.fixed)[names(SD$par.fixed) =="log_B_dev"])
    }
    SE_Dev_out <- est_B_dev
    SE_Dev_out[is.na(SE_Dev_out)] <- 0
    SE_Dev_out[!is.na(SE_Dev_out)] <- SE_Dev

    Assessment@SE_UMSY <- SD$sd[names(SD$value) == "UMSY"]
    Assessment@SE_MSY <- SD$sd[names(SD$value) == "MSY"]
    Assessment@SE_U_UMSY_final <- SD$sd[names(SD$value) == "U_UMSY_final"]
    Assessment@SE_B_BMSY_final <- SD$sd[names(SD$value) == "B_BMSY_final"]
    Assessment@SE_B_B0_final <- SD$sd[names(SD$value) == "B_K_final"]
    Assessment@SE_VB_VBMSY_final <- SD$sd[names(SD$value) == "B_BMSY_final"]
    Assessment@SE_VB_VB0_final <- SD$sd[names(SD$value) == "B_K_final"]
    Assessment@SE_Dev <- structure(SE_Dev_out, names = Year)
  }
  return(Assessment)
}
class(SP_SS) <- "Assess"
