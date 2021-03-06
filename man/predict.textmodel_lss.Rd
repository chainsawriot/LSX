% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/textmodel.R
\name{predict.textmodel_lss}
\alias{predict.textmodel_lss}
\title{Prediction method for textmodel_lss}
\usage{
\method{predict}{textmodel_lss}(
  object,
  newdata = NULL,
  se.fit = FALSE,
  density = FALSE,
  rescaling = TRUE,
  ...
)
}
\arguments{
\item{object}{a fitted LSS textmodel}

\item{newdata}{dfm on which prediction should be made}

\item{se.fit}{if \code{TRUE}, it returns standard error of document scores.}

\item{density}{if \code{TRUE}, returns frequency of model terms in documents.
Density distribution of model terms can be used to remove documents about
unrelated subjects.}

\item{rescaling}{if \code{TRUE}, scores are normalized using \code{scale()}.}

\item{...}{not used}
}
\description{
Prediction method for textmodel_lss
}
\keyword{internal}
