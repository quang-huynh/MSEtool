% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/SP.R
\name{SP}
\alias{SP}
\alias{SP_SS}
\title{Surplus production model with UMSY and MSY as leading parameters}
\usage{
SP(x = 1, Data, rescale = "mean1", start = NULL, fix_dep = TRUE,
  fix_n = TRUE, silent = TRUE, opt_hess = FALSE,
  n_restart = ifelse(opt_hess, 0, 1), control = list(iter.max = 5000,
  eval.max = 10000), ...)

SP_SS(x = 1, Data, rescale = "mean1", start = NULL, fix_dep = TRUE,
  fix_n = TRUE, fix_sigma = TRUE, fix_tau = TRUE, early_dev = c("all",
  "index"), integrate = FALSE, silent = TRUE, opt_hess = FALSE,
  n_restart = ifelse(opt_hess, 0, 1), control = list(iter.max = 5000,
  eval.max = 10000), inner.control = list(), ...)
}
\arguments{
\item{x}{An index for the objects in \code{Data} when running in closed loop simulation.
Otherwise, equals to 1 When running an assessment interactively.}

\item{Data}{An object of class Data.}

\item{rescale}{A multiplicative factor that rescales the catch in the assessment model, which
can improve convergence. By default, \code{"mean1"} scales the catch so that time series mean is 1, otherwise a numeric.
Output is re-converted back to original units.}

\item{start}{Optional list of starting values. See details.}

\item{fix_dep}{Logical, whether to fix the initial depletion (ratio of biomass to carrying capacity in the
first year of the model). If \code{TRUE}, uses the value in \code{start}, otherwise equal to 1
(assumes virgin conditions).}

\item{fix_n}{Logical, whether to fix the exponent of the production function. If \code{TRUE},
uses the value in \code{start}, otherwise equal to \code{n = 2}, where the biomass at MSY
is half of carrying capacity.}

\item{silent}{Logical, passed to \code{\link[TMB]{MakeADFun}}, whether TMB
will print trace information during optimization. Used for dignostics for model convergence.}

\item{opt_hess}{Logical, whether the hessian function will be passed to \code{\link[stats]{nlminb}} during optimization
(this generally reduces the number of iterations to convergence, but is memory and time intensive and does not guarantee an increase
in convergence rate). Ignored if \code{integrate = TRUE}.}

\item{n_restart}{The number of restarts (calls to \code{\link[stats]{nlminb}}) in the optimization procedure, so long as the model
hasn't converged. The optimization continues from the parameters from the previous (re)start.}

\item{control}{A named list of parameters regarding optimization to be passed to
\code{\link[stats]{nlminb}}.}

\item{...}{Additional arguments (not currently used).}

\item{fix_sigma}{Logical, whether the standard deviation of the index is fixed. If \code{TRUE},
sigma is fixed to value provided in \code{start} (if provided), otherwise, value based on \code{Data@CV_Ind}.}

\item{fix_tau}{Logical, the standard deviation of the biomass deviations is fixed. If \code{TRUE},
tau is fixed to value provided in \code{start} (if provided), otherwise, equal to 1.}

\item{early_dev}{Character string describing the years for which biomass deviations are estimated in \code{SP_SS}.
By default, deviations are estimated in each year of the model (\code{"all"}), while deviations could also be estimated
once index data are available (\code{"index"}).}

\item{integrate}{Logical, whether the likelihood of the model integrates over the likelihood
of the biomass deviations (thus, treating it as a state-space variable).}

\item{inner.control}{A named list of arguments for optimization of the random effects, which
is passed on to \link[TMB]{newton} via \code{\link[TMB]{MakeADFun}}.}
}
\value{
An object of \code{\linkS4class{Assessment}} containing objects and output
from TMB.
}
\description{
A surplus production model that estimates the TAC using a
time-series of catches and a relative abundance index and coded in TMB.
The model is conditioned on catch and estimates a predicted index. The state-space version
estimates annual deviates in biomass.
}
\details{
To provide starting values for the \code{SP}, a named list can be provided for \code{UMSY},
\code{MSY}, \code{dep}, and \code{n} via the start argument (see example).

For \code{SP_SS}, a start value can also be provided for \code{sigma} and \code{tau}, the standard deviation
of the index and log-biomass deviates, respectively. Deviations are estimated beginning in the year when index
data are available.
}
\section{Functions}{
\itemize{
\item \code{SP}: Fixed effects model

\item \code{SP_SS}: State-space version
}}

\note{
The model uses the Fletcher (1978) formulation and is parameterized with UMSY and MSY as
leading parameters. The default conditions assume virgin conditions in the first year of the time series
and a symmetric production function.
}
\section{Required Data}{

\itemize{
\item \code{SP}: Cat, Ind
\item \code{SP_SS}: Cat, Ind
}
}

\section{Optional Data}{

\code{SP_SS}: CV_Ind
}

\examples{
\donttest{
data(swordfish)

#### Observation-error surplus production model
res <- SP(Data = swordfish)

# Provide starting values, assume B/K = 0.95 in first year of model
# and symmetrical production curve (n = 2)
start <- list(UMSY = 0.1, MSY = 1e5, dep = 0.95, n = 2)
res <- SP(Data = swordfish, start = start)

#### State-space version
res <- SP_SS(Data = swordfish, start = list(dep = 0.95, tau = 0.3),
fix_sigma = TRUE)
}
}
\references{
Fletcher, R. I. 1978. On the restructuring of the Pella-Tomlinson system.
Fishery Bulletin 76:515:521.

Pella, J. J. and Tomlinson, P. K. 1969. A generalized stock production model.
Inter-Am. Trop. Tuna Comm., Bull. 13:419-496.
}
\seealso{
\link{SP_production}

\link{plot,Assessment,ANY-method} \link{summary,Assessment-method} \link{retrospective} \link{profile_likelihood} \link{make_MP}
}
\author{
Q. Huynh
}
