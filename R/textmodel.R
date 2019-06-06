#' A vector-space model for subject specific sentiment-analysis
#'
#' @param x a dfm created by \code{\link[quanteda]{dfm}}
#' @param seeds a character vector, named numeric vector or dictionary that
#'   contains seed words.
#' @param features featues of a dfm to be included in the model as terms. This
#'   argument is used to make models only sensitive to subject specific words.
#' @param k the size of semantic space passed to the SVD engine
#' @param simil_method specifies method to compute similiaty between features.
#'   The value is passed to \code{\link[quanteda]{textstat_simil}}, "cosine" is
#'   used otherwise.
#' @param cache if \code{TRUE}, save retult of SVD for next execution with
#'   identical \code{x} and \code{k}.
#' @param include_data if \code{TRUE}, fitted model include the dfm supplied as
#'   \code{x}.
#' @param engine choose SVD engine between \code{\link[RSpectra]{svds}} and
#'   \code{\link[irlba]{irlba}}
#' @param s the number factors used to compute similiaty between features.
#' @param verbose show messages if \code{TRUE}.
#' @param ... additional argument passed to the SVD engine
#' @import quanteda
#' @export
#' @references Watanabe, Kohei. "Measuring News Bias: Russia's Official News
#'   Agency ITAR-TASS' Coverage of the Ukraine Crisis." European Journal of
#'   Communication 32, no. 3 (March 20, 2017): 224–41.
#'   https://doi.org/10.1177/0267323117695735.
#' @examples
#' require(quanteda)
#'
#' load('/home/kohei/Dropbox/Public/guardian-sample.RData')
#' corp <- corpus_reshape(data_corpus_guardian, 'sentences')
#' toks <- tokens(corp, remove_punct = TRUE)
#' mt <- dfm(toks, remove = stopwords())
#' mt <- dfm_trim(mt, min_termfreq = 10)
#' lss <- textmodel_lss(mt, seedwords('pos-neg'))
#' summary(lss)
#'
#' # sentiment model on economy
#' eco <- head(char_keyness(toks, 'econom*'), 500)
#' lss_eco <- textmodel_lss(mt, seedwords('pos-neg'), features = eco)
#'
#' # sentiment model on politics
#' pol <- head(char_keyness(toks, 'politi*'), 500)
#' lss_pol <- textmodel_lss(mt, seedwords('pos-neg'), features = pol)
textmodel_lss <- function(x, seeds, features = NULL, k = 300, cache = FALSE,
                          simil_method = "cosine", include_data = TRUE,
                          engine = c("RSpectra", "irlba"), s = k,
                          verbose = FALSE, ...) {

    engine <- match.arg(engine)

    if (is.dfm(features))
        stop("features cannot be a dfm\n", call. = FALSE)

    if (is.dictionary(seeds))
        seeds <- unlist(seeds, use.names = FALSE)

    # give equal weight to characters
    if (is.character(seeds))
        seeds <- structure(rep(1, length(seeds)), names = seeds)

    if (is.null(names(seeds)))
        stop("y must be a named-numerid vector\n", call. = FALSE)

    # generate inflected seed
    seeds_weighted <- mapply(weight_seeds, names(seeds), unname(seeds) / length(seeds),
                             MoreArgs = list(featnames(x)), USE.NAMES = TRUE, SIMPLIFY = FALSE)
    seed <- unlist(unname(seeds_weighted))

    if (verbose)
        cat("Calculating term-term similarity to", sum(lengths(seeds)), "seed words...\n")

    if (verbose)
        cat("Starting singular value decomposition of dfm...\n")

    if (all(lengths(seeds_weighted) == 0))
        stop("No seed word is found in the dfm", call. = FALSE)

    if (verbose)
        cat("Performing SVD by ", engine, "...\n")
    svd <- cache_svd(x, k, engine, cache, ...)
    embed <- get_embedding(svd, featnames(x))

    # identify relevance to seed words
    cos <- proxyC::simil(embed[,names(seed),drop = FALSE],
                         Matrix::Matrix(seed, nrow = 1, sparse = TRUE),
                         margin = 1)
    relev <- abs(as.numeric(cos))
    if (s < k) {
        l <- rank(relev) >= s
    } else {
        l <- rep(TRUE, nrow(embed))
    }

    simil <- as.matrix(proxyC::simil(embed[l,,drop = FALSE], embed[l,names(seed),drop = FALSE],
                                     margin = 2, method = simil_method))
    simil_seed <- simil[rownames(simil) %in% names(seed),
                        colnames(simil) %in% names(seed), drop = FALSE]
    if (!is.null(features))
        simil <- simil[unlist(pattern2fixed(features, rownames(simil), "glob", FALSE)),,drop = FALSE]
    if (!identical(colnames(simil), names(seed)))
        stop("Columns and seed words do not match", call. = FALSE)

    result <- list(beta = sort(rowMeans(simil %*% seed), decreasing = TRUE),
                   features = if (is.null(features)) featnames(x) else features,
                   seeds = seeds,
                   seeds_weighted = seeds_weighted,
                   embedding = embed,
                   similarity = simil_seed,
                   relevance = relev,
                   importance = svd$d,
                   call = match.call())

    if (include_data)
        result$data <- x
    class(result) <- "textmodel_lss"
    return(result)
}

cache_svd <- function(x, k, engine, cache = TRUE, ...) {

    hash <- digest::digest(list(as(x, "dgCMatrix"), k, engine), algo = "xxhash64")
    if (cache && !dir.exists("lss_cache"))
        dir.create("lss_cache")
    if (engine == "RSpectra") {
        file_cache <- paste0("lss_cache/svds_", hash, ".RDS")
    } else {
        file_cache <- paste0("lss_cache/irlba_", hash, ".RDS")
    }
    # only for backward compatibility
    file_cache_old <- paste0("lss_cache_", hash, ".RDS")
    if (file.exists(file_cache_old))
        file.rename(file_cache_old, file_cache)

    if (cache && file.exists(file_cache)){
        message("Reading cache file: ", file_cache)
        result <- readRDS(file_cache)
    } else {
        if (engine == "RSpectra") {
            result <- RSpectra::svds(as(x, "dgCMatrix"), k = k, nu = 0, nv = k, ...)
        } else {
            result <- irlba::irlba(as(x, "dgCMatrix"), k = k, right_only = TRUE, ...)
        }
        if (cache) {
            message("Writing cache file: ", file_cache)
            saveRDS(result, file_cache)
        }
    }
    return(result)
}

get_embedding <- function(svd, feature) {
    result <- t(svd$v * svd$d)
    colnames(result) <- feature
    Matrix::Matrix(result, sparse = TRUE)
}

#' @export
#' @noRd
#' @importFrom stats coef
#' @importFrom utils head
#' @method summary textmodel_lss
summary.textmodel_lss <- function(object, n = 30L, ...) {
    result <- list(
        "call" = object$call,
        "seeds" = object$seeds,
        "weighted.seeds" = object$seeds_weighted,
        "beta" = as.coefficients_textmodel(head(coef(object), n))
    )
    if (!any("data" == names(object)))
        result$data.dimension <- dim(object$data)
    as.summary.textmodel(result)
}

#' Extract model coefficients from a fitted textmodel_lss object
#'
#' \code{coef()} extract model coefficients from a fitted \code{textmodel_lss}
#' object.  \code{coefficients()} is an alias.
#' @param object a fitted \link{textmodel_lss} object
#' @param ... unused
#' @keywords textmodel internal
#' @export
coef.textmodel_lss <- function(object, ...) {
    object$beta
}

#' @rdname coef.textmodel_lss
#' @export
coefficients.textmodel_lss <- function(object, ...) {
    UseMethod("coef")
}

#' Internal function to generate equally-weighted seed set
#'
#' @keywords internal
weight_seeds <- function(seed, weight, type) {
    s <- unlist(pattern2fixed(seed, type, "glob", FALSE))
    v <- rep(weight / length(s), length(s))
    names(v) <- s
    return(v)
}

#' Prediction method for textmodel_lss
#' @param object a fitted LSS textmodel
#' @param newdata dfm on which prediction should be made
#' @param se.fit if \code{TRUE}, it returns standard error of document scores.
#' @param density if \code{TRUE}, returns frequency of features in documents.
#'   Density distribution of features can be used to remove documents about
#'   unrelated subjects.
#' @param rescaling if \code{TRUE}, scores are reslaced using \code{scale()}.
#' @param ... not used
#' @import methods
#' @export
predict.textmodel_lss <- function(object, newdata = NULL, se.fit = FALSE,
                                  density = FALSE, rescaling = TRUE, ...){

    model <- as.dfm(rbind(object$beta))

    if (is.null(newdata)) {
        if (!any("data" == names(object)))
            stop("LSS model includes no data, please supply a dfm using newdata.\n")
        data <- object$data
    } else {
        if (!is.dfm(newdata))
            stop("newdata must be a dfm\n", call. = FALSE)
        data <- newdata
    }

    d <- unname(rowSums(dfm_select(dfm_weight(data, "prop"), object$features)))
    if (!identical(featnames(data), featnames(model)))
        data <- dfm_select(data, model)

    n <- unname(Matrix::rowSums(data))
    data <- dfm_weight(data, "prop")
    model <- as(model, "dgCMatrix")
    fit <- Matrix::rowSums(data %*% Matrix::t(model)) # mean scores of documents
    fit[n == 0] <- NA

    if (rescaling) {
        fit_scaled <- scale(fit)
        result <- list(fit = rowSums(fit_scaled))
    } else {
        result <- list(fit = fit)
    }

    if (se.fit) {
        m <- matrix(rep(fit, ncol(data)), nrow = ncol(data), byrow = TRUE)
        error <- t(m - model[,colnames(data)]) ^ 2
        var <- unname(Matrix::rowSums(data * error))
        se <- ifelse(n == 0, NA, sqrt(var) / sqrt(n))
        if (rescaling)
            se <- se / attr(fit_scaled, "scaled:scale")
        result$se.fit <- se
        result$n <- n
    }
    if (density)
        result$density <- d

    if (!se.fit && !density) {
        return(result$fit)
    } else {
        return(result)
    }
}

#' Identify keywords occur frequently with target words
#'
#' @param x tokens object created by \code{\link[quanteda]{tokens}}.
#' @param pattern to specify target words. See \code{\link[quanteda]{pattern}} for details.
#' @param valuetype the type of pattern matching: \code{"glob"} for
#'   "glob"-style wildcard expressions; \code{"regex"} for regular expressions;
#'   or \code{"fixed"} for exact matching. See \code{\link[quanteda]{valuetype}} for details.
#' @param case_insensitive ignore case when matching, if \code{TRUE}
#' @param window size of window for collocation analysis.
#' @param p threashold for statistical significance of collocaitons.
#' @param min_count minimum frequency for words within the window to be
#'   considered as collocations.
#' @param remove_pattern if \code{TRUE}, keywords do not containe target words.
#' @param ... additional arguments passed to \code{\link{textstat_keyness}}.
#' @export
#' @seealso \code{\link{tokens_select}} and \code{\link{textstat_keyness}}
#' @examples
#' require(quanteda)
#' load('/home/kohei/Dropbox/Public/guardian-sample.RData')
#' corp <- corpus_reshape(data_corpus_guardian, 'sentences')
#' toks <- tokens(corp, remove_punct = TRUE)
#' toks <- tokens_remove(toks, stopwords())
#'
#' # economy keywords
#' eco <- char_keyness(toks, 'econom*')
#' head(eco, 20)
#'
#' # politics keywords
#' pol <- char_keyness(toks, 'politi*')
#' head(pol, 20)
char_keyness <- function(x, pattern, valuetype = c("glob", "regex", "fixed"),
                         case_insensitive = TRUE, window = 10, p = 0.001, min_count = 10,
                         remove_pattern = TRUE, ...) {
    if (!is.tokens(x))
        stop("x must be a tokens object\n", call. = FALSE)

    # reference
    ref <- dfm(tokens_remove(x, pattern, valuetype = valuetype,
                           case_insensitive = case_insensitive,
                           window = window), remove = "")

    # target
    x <- tokens_select(x, pattern, valuetype = valuetype,
                      case_insensitive = case_insensitive,
                      window = window)
    if (remove_pattern)
        x <- tokens_remove(x, pattern, valuetype = valuetype,
                           case_insensitive = case_insensitive)

    tar <- dfm(x, remove = "")
    if (nfeat(tar) == 0)
        stop(paste(unlist(pattern), collapse = ", "), " is not found\n", call. = FALSE)
    tar <- dfm_trim(tar, min_termfreq = min_count)
    if (nfeat(tar) == 0)
        return(character())
    ref <- dfm_match(ref, featnames(tar))
    key <- textstat_keyness(rbind(tar, ref), target = seq_len(ndoc(tar)), ...)
    key <- key[key$p < p,]
    return(key$feature)
}

#' Seed words for sentiment analysis
#'
#' @param type type of seed words currently only for sentiment (\code{pos-neg})
#'   or political ideology (\code{left-right}).
#' @export
#' @examples
#' seedwords('pos-neg')
#' @references Turney, P. D., & Littman, M. L. (2003). Measuring Praise and
#'   Criticism: Inference of Semantic Orientation from Association. ACM Trans.
#'   Inf. Syst., 21(4), 315–346. https://doi.org/10.1145/944012.944013
seedwords <- function(type) {

    if (type == "pos-neg") {
        seeds <- c(rep(1, 7), rep(-1, 7))
        names(seeds) <- c("good", "nice", "excellent", "positive", "fortunate", "correct", "superior",
                          "bad", "nasty", "poor", "negative", "unfortunate", "wrong", "inferior")
    } else if (type == "left-right") {
        seeds <- c(rep(1, 7), rep(-1, 7))
        names(seeds) <- c("deficit", "austerity", "unstable", "recession", "inflation", "currency", "workforce",
                          "poor", "poverty", "free", "benefits", "prices", "money", "workers")
    } else {
        stop(type, "is not currently available", call. = FALSE)
    }
    return(seeds)
}

#' Create a dummy textmodel_lss object from numeric vector
#' @param x named numeric vector
#' @keywords internal
#' @export
as.textmodel_lss <- function(x) {

    stopifnot(is.numeric(x))
    stopifnot(!is.null(names(x)))

    result <- list(beta = x,
                   data = NULL,
                   features = names(x),
                   seeds = character(),
                   seeds_weighted = character(),
                   call = match.call())
    class(result) <- "textmodel_lss"
    return(result)
}

#' Smooth predicted LSS scores by local polynomial regression
#'
#' @param x a \code{data.frame} containing variables for LSS scores and dates
#' @param lss_var the name of the column for LSS scores
#' @param date_var the name of the columns for dates
#' @param span determines the level of smoothing
#' @param from start of the time period
#' @param to end of the time period
#' @param ... extra arguments passed to \code{\link{loess}}
#' @export
#' @import stats
smooth_lss <- function(x, lss_var = "fit", date_var = "date", span = 0.1,
                       from = NULL, to = NULL, ...) {
    if (!lss_var %in% names(x) || !identical(class(x[[lss_var]]), "numeric"))
        stop("x must have a numeric variable for LSS scores")
    if (!date_var %in% names(x) || !identical(class(x[[date_var]]), "Date"))
        stop("x must have a date variable for dates")
    x$lss <- x[[lss_var]]
    x$date <- x[[date_var]]
    if (is.null(from))
        from <- min(x$date)
    if (is.null(to))
        to <- max(x$date)
    x$time <- as.numeric(difftime(x$date, from, units = "days"))
    dummy <- data.frame(date = seq(from, to, '1 day'))
    dummy$time <- as.numeric(difftime(dummy$date, from, units = "days"))
    dummy$fit <- NA
    suppressWarnings(
        temp <- predict(loess(lss ~ time, data = x, span = span, ...),
                        newdata = dummy, se = TRUE)
    )
    result <- cbind(dummy[c("date", "time")], temp[c("fit", "se.fit")])
    return(result)
}