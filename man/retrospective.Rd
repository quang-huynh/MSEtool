% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/report_core.R
\name{retrospective}
\alias{retrospective}
\title{Retrospective analysis of assessment models}
\usage{
retrospective(Assessment, nyr = 5, figure = TRUE, save_figure = TRUE,
  save_dir = tempdir())
}
\arguments{
\item{Assessment}{An S4 object of class \linkS4class{Assessment}.}

\item{nyr}{The maximum number of years to remove for the retrospective analysis.}

\item{figure}{Indicates whether plots will be drawn.}

\item{save_figure}{Indicates whether figures will be saved to directory.}

\item{save_dir}{The directory to which figures will be saved. By default: \code{getwd()}}
}
\value{
A list with an array of model output and of model estimates from
the retrospective analysis.

Figures showing the time series of biomass and exploitation and parameter estimates
with successive number of years removed. Returns invisibly a list of model output and model estimates.
}
\description{
Perform a retrospective analysis, successive removals of most recent years of data to evaluate resulting
parameter estimates.
}
\examples{
\donttest{
output <- DD_TMB(Data = DLMtool::Red_snapper)
get_retro <- retrospective(output, nyr = 5, figure = FALSE)
}
}
\author{
Q. Huynh
}
