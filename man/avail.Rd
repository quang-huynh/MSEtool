% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Misc_exported.R
\name{avail}
\alias{avail}
\title{What objects of this class are available}
\usage{
avail(classy)
}
\arguments{
\item{classy}{A class of object (character string, e.g. 'Fleet')}
}
\description{
Generic class finder
}
\details{
Finds objects of the specified class in the global environment or in the
MSEtool and DLMtool packages. This function is an addendum to the \code{\link[DLMtool]{avail}}
function in DLMtool.
}
\examples{
avail("Assess")
avail("HCR")
avail("Stock")
}
\author{
Q. Huynh
}