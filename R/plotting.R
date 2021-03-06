#' Methimpute plotting functions
#' 
#' This page provides an overview of all \pkg{\link{methimpute}} plotting functions.
#'
#' @param model A \code{\link{methimputeBinomialHMM}} object.
#' @param datapoints The number of randomly selected datapoints for the plot.
#' @param binwidth The bin width for the histogram/boxplot.
#' @return A \code{\link[ggplot2]{ggplot}} object.
#' @name plotting
#' @import ggplot2
#' @examples 
#'## Get some toy data
#'file <- system.file("data","arabidopsis_toydata.RData",
#'                     package="methimpute")
#'data <- get(load(file))
#'print(data)
#'model <- callMethylation(data)
#'## Make nice plots
#'plotHistogram(model, total.counts=5)
#'plotScatter(model)
#'plotTransitionProbs(model)
#'plotConvergence(model)
#'plotPosteriorDistance(model$data)
#'
#'## Get annotation data and make an enrichment profile
#'# Note that this looks a bit ugly because our toy data
#'# has only 200000 datapoints.
#'data(arabidopsis_genes)
#'plotEnrichment(model, annotation=arabidopsis_genes)
#'
NULL

#' Get state colors
#'
#' Get the colors that are used for plotting.
#'
#' @param states A character vector.
#' @return A character vector with colors.
#' @seealso \code{\link{plotting}}
#' @export
#'@examples
#'cols <- getStateColors()
#'pie(1:length(cols), col=cols, labels=names(cols))
getStateColors <- function(states=NULL) {
    state.colors <- c("Background" = "gray", "Unmethylated" = "red","Methylated" = "blue","Intermediate" = "green", "Total" = "black", "Signal" = "red")
    if (is.null(states)) {
        return(state.colors)
    } else {
        states <- as.character(states)
        states.other <- setdiff(states, names(state.colors))
        if (length(states.other) > 0) {
            state.colors.other <- getDistinctColors(states.other)
            state.colors <- c(state.colors, state.colors.other)
        }
        return(state.colors[states])
    }
}


#' Transform genomic coordinates
#'
#' Add two columns with transformed genomic coordinates to the \code{\link{GRanges}} object. This is useful for making genomewide plots.
#'
#' @param gr A \code{\link{GRanges}} object.
#' @return The input \code{\link{GRanges}} with two additional metadata columns 'start.genome' and 'end.genome'.
transCoord <- function(gr) {
    cum.seqlengths <- cumsum(as.numeric(seqlengths(gr)))
    cum.seqlengths.0 <- c(0,cum.seqlengths[-length(cum.seqlengths)])
    names(cum.seqlengths.0) <- seqlevels(gr)
    gr$start.genome <- start(gr) + cum.seqlengths.0[as.character(seqnames(gr))]
    gr$end.genome <- end(gr) + cum.seqlengths.0[as.character(seqnames(gr))]
    return(gr)
}


#' @describeIn plotting Plot a histogram of count values and fitted distributions.
#' @param total.counts The number of total counts for which the histogram is to be plotted.
#' @importFrom stats dbinom
#' @export
plotHistogram <- function(model, total.counts, binwidth=1) {

    if (class(model) == 'GRanges') {
        model <- list(data=model)
    }
    ## Get cross section at total counts ##
    counts <- model$data$counts
    mask.crosssec <- counts[,'total'] == total.counts
    counts.methylated <- counts[mask.crosssec,'methylated']
    
    contexts <- intersect(levels(model$data$context), unique(model$data$context))
    ## Histogram ##
    df <- data.frame(counts=counts.methylated, context=model$data$context[mask.crosssec])
    ggplt <- ggplot(df) + geom_histogram(aes_string(x='counts', y='..density..'), binwidth=binwidth, color='black', fill='white')
    ggplt <- ggplt + theme_bw()
    ggplt <- ggplt + xlab(paste0("methylated counts\nat positions with total counts = ", total.counts))
    ggplt <- ggplt + coord_cartesian(xlim=c(0,total.counts))
    ggplt <- ggplt + facet_wrap(~ context)
    
    ## Fits ##
    if (!is.null(model$params$emissionParams)) {
        x <- seq(0, total.counts, by = binwidth)
        distr.list <- list()
        for (context in contexts) {
            distr <- list(x=x)
            for (i1 in 1:length(model$params$emissionParams)) {
                e <- model$params$emissionParams[[i1]]
                distr[[names(model$params$emissionParams)[i1]]] <- model$params$weights[[context]][i1] * stats::dbinom(x, size=total.counts, prob=e[context,'prob'])
            }
            distr <- as.data.frame(distr)
            distr$Total <- rowSums(distr[,-1])
            distr$context <- context
            distr.list[[context]] <- distr
        }
        distr <- do.call(rbind, distr.list)
        distr <- reshape2::melt(distr, id.vars=c('x', 'context'), variable.name='components')
        distr$components <- sub('^X', '', distr$components)
        distr$components <- factor(distr$components, levels=c('Total', levels(model$data$status)))
        ggplt <- ggplt + geom_line(data=distr, mapping=aes_string(x='x', y='value', col='components'))
        
        # ## Make legend
        # lprobs <- round(sapply(model$params$emissionParams, function(x) { x[,'prob'] }), 4)
        # lweights <- round(model$params$weights[[context]], 2)
        # legend <- paste0(names(model$params$emissionParams), ", prob=", lprobs, ", weight=", lweights)
        # legend <- c(paste0("Total, weight=", round(sum(lweights))), legend)
        # ggplt <- ggplt + scale_color_manual(name="components", values=getStateColors(levels(distr$components)), labels=legend) + theme(legend.position=c(0.5,0.99), legend.justification=c(0.5,1))
        
        ## Make legend
        # lprobs <- round(sapply(model$params$emissionParams, function(x) { x[,'prob'] }), 4)
        # rownames(lprobs) <- rownames(model$params$emissionParams[[1]])
        # lprobs <- lprobs[contexts,]
        # lweights <- round(t(as.data.frame(model$params$weights)), 2)
        # lweights <- lweights[contexts,]
        ggplt <- ggplt + scale_color_manual(name="components", values=getStateColors(levels(distr$components))) + theme(legend.position=c(0.5,0.99), legend.justification=c(0.5,1))
    }
    ggplt <- ggplt + ggtitle('Fitted distributions')
        
    return(ggplt)

}


#' @describeIn plotting Plot a scatter plot of read counts colored by methylation status.
#' @export
plotScatter <- function(model, datapoints=1000) {

    contexts <- intersect(levels(model$data$context), unique(model$data$context))
    ggplts <- list()
    limits <- list()
    data <- model$data
    ## Find sensible limits
    xmax <- quantile(data$counts[,'total']-data$counts[,'methylated'], 0.99)
    ymax <- quantile(data$counts[,'methylated'], 0.99)
    limits <- c(xmax, ymax)
    df <- data.frame(status=data$status, unmethylated=data$counts[,'total']-data$counts[,'methylated'], methylated=data$counts[,'methylated'], context=data$context)
    if (datapoints < nrow(df)) {
        df <- df[sample(1:nrow(df), datapoints, replace = FALSE), ]
    }
    
    ggplt <- ggplot(df, aes_string(x='methylated', y='unmethylated', col='status'))
    ggplt <- ggplt + geom_point(alpha=0.3)
    ggplt <- ggplt + coord_cartesian(xlim=c(0,xmax), ylim=c(0,ymax))
    ggplt <- ggplt + theme_bw()
    ggplt <- ggplt + xlab('methylated counts') + ylab('unmethylated counts')
    ggplt <- ggplt + facet_wrap(~ context)
    ggplt <- ggplt + scale_color_manual(values=getStateColors(levels(df$status)))
    
    # ## Legend
    # lweights <- round(model$params$weights[[context]], 2)
    # legend <- paste0(names(model$params$weights[[context]]), ", weight=", lweights)
    # ggplt <- ggplt + scale_color_manual(values=getStateColors(names(model$params$weights[[context]])), labels=legend)
    # ggplt <- ggplt + theme(legend.position=c(1,1), legend.justification=c(1,1))
    
    ggplt <- ggplt + ggtitle('Classification')
    
    return(ggplt)
    
}


#' @describeIn plotting Plot a heatmap of transition probabilities.
#' @importFrom reshape2 melt
#' @export
plotTransitionProbs <- function(model) {

    if (is.list(model$params$transProbs)) {
        As <- model$params$transProbs
    } else if (is.matrix(model$params$transProbs)) {
        As <- list(transitions=model$params$transProbs)
    }

    A <- reshape2::melt(As, varnames=c('from','to'), value.name='prob')
    names(A)[4] <- 'transitionContext'
    A$from <- factor(A$from, levels=rev(unique(A$from)))
    A$to <- factor(A$to, levels=rev(unique(A$from)))
    ggplt <- ggplot(data=A) + geom_tile(aes_string(x='to', y='from', fill='prob')) + scale_fill_gradient(low="white", high="blue", limits=c(0,1)) + theme_bw() + theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust=0.5))
    ggplt <- ggplt + facet_wrap(~ transitionContext)
    
    ggplt <- ggplt + ggtitle('Transition probabilities')
    
    return(ggplt)

}

insertNULL <- function(plotlist) {
    n <- 0.5 * ( sqrt(8*length(plotlist)+1) - 1 )
    plotlist2 <- list()
    i3 <- 1
    for (i1 in 1:n) {
        if (i1 > 1) {
            for (i2 in 1:(n-i1)) {
                plotlist2[length(plotlist2)+1] <- list(NULL)
            }
        }
        for (i2 in i1:n) {
            plotlist2[[length(plotlist2)+1]] <- plotlist[[i3]]
            i3 <- i3 + 1
        }
    }
    return(plotlist2)
}

#' @describeIn plotting Plot the convergence of the probability parameters.
#' @export
plotConvergence <- function(model) {
    
    info <- model$convergenceInfo$prefit
    if (is.null(info)) {
        info <- model$convergenceInfo
    }
    # ## Plot loglikelihood
    # df <- data.frame(iteration=0:(length(info$logliks)-1), loglik=info$logliks)
    # ggplt <- ggplot(df) + geom_line(aes_string(x='iteration', y='loglik')) + theme_bw()
    # ggplt <- ggplt + scale_x_continuous(breaks=df$iteration, limits=c(2, length(info$logliks)-1))
    
    ## Plot parameters
    df <- reshape2::melt(info$parameterInfo, value.name='prob')
    ggplt <- ggplot(df) + geom_line(aes_string(x='iteration', y='prob', col='status')) + theme_bw()
    ggplt <- ggplt + theme(panel.grid.minor.x = element_blank())
    ggplt <- ggplt + facet_wrap(~ context)
    ggplt <- ggplt + scale_y_continuous(limits=c(0,1))
    ggplt <- ggplt + scale_color_manual(values=getStateColors(unique(df$status)))
    
    ggplt <- ggplt + ggtitle('Baum-Welch convergence')
    
    return(ggplt)
}


#' @describeIn plotting Plot an enrichment profile around an annotation.
#' @param annotation A \code{\link[GenomicRanges]{GRanges}} object with coordinates for the annotation.
#' @param windowsize Resolution in base-pairs for the curve upstream and downstream of the annotation.
#' @param insidewindows Number of data points for the curve inside the annotation.
#' @param range Distance upstream and downstream for which the enrichment profile is calculated.
#' @param category.column The name of a column in \code{data} that will be used for facetting of the plot.
#' @param plot Logical indicating whether a plot or the underlying data.frame is to be returned.
#' @param df.list A list() of data.frames, output from \code{plotEnrichment(..., plot=FALSE)}. If specified, option \code{data} will be ignored.
#' @export
plotEnrichment <- function(model, annotation, windowsize=100, insidewindows=20, range=1000, category.column=NULL, plot=TRUE, df.list=NULL) {
    ## For debugging
    # windowsize=100; insidewindows=20; range=1000; category.column=NULL
    # annotation <- arabidopsis_genes
    # model$data$imputed <- FALSE
    # model$data$imputed[model$data$counts[,'total'] == 0] <- TRUE
    # model$data$imputed <- factor(model$data$imputed)
    # category.column <- 'imputed'
    # data <- model$data

    if (class(model) == 'methimputeBinomialHMM') {
        data <- model$data
        distr <- model$params$emissionParams
    } else if (class(model) == 'GRanges') {
        data <- model
        distr <- NULL
    } else {
        stop("Argument 'model' needs to be of class 'GRanges' or 'methimputeBinomialHMM'.")
    }
    if (is.null(df.list)) {
        ## Variables
        categories <- 'none'
        if (!is.null(category.column)) {
            categories <- levels(mcols(data)[,category.column])
        }
        if (is.null(data$meth.lvl)) {
            data$meth.lvl <- data$counts[,'methylated'] / data$counts[,'total']
        }
        if (is.null(data$rc.meth.lvl) & !is.null(distr)) {
            if (!is.null(distr$Intermediate)) {
                data$rc.meth.lvl <- distr$Unmethylated[data$context,] * data$posteriorUnmeth + distr$Intermediate[data$context,] * (1 - data$posteriorUnmeth - data$posteriorMeth) + distr$Methylated[data$context,] * data$posteriorMeth
            } else {
                data$rc.meth.lvl <- distr$Unmethylated[data$context,] * data$posteriorUnmeth + distr$Methylated[data$context,] * data$posteriorMeth
            }
        }
        
        ## Subset annotation to data range
        annotation <- subsetByOverlaps(annotation, data)

        overlaps.rc.meth.lvl <- array(NA, dim=c(length(levels(data$context)), length(categories), range%/%windowsize, 2, 2), dimnames=list(context=levels(data$context), category=categories, distance=1:(range%/%windowsize), what=c('mean', 'weight'), where=c('upstream', 'downstream')))
        overlaps.meth.lvl <- array(NA, dim=c(length(levels(data$context)), length(categories), range%/%windowsize, 2, 2), dimnames=list(context=levels(data$context), category=categories, distance=1:(range%/%windowsize), what=c('mean', 'weight'), where=c('upstream', 'downstream')))
        ## Upstream and downstream annotation
        annotation.up <- resize(x = annotation, width = 1, fix = 'start')
        annotation.down <- resize(x = annotation, width = 1, fix = 'end')
        for (context in levels(data$context)) {
            message("Upstream and downstream counts for context ", context)
            data.context <- data[data$context == context]
            for (category in categories) {
                message("  category ", category)
                if (!is.null(category.column)) {
                    data.category <- data.context[mcols(data.context)[,category.column] == category]
                } else {
                    data.category <- data.context
                }
                for (i1 in 1:(range %/% windowsize)) {
                    anno.up <- suppressWarnings( promoters(x = annotation.up, upstream = i1*windowsize, downstream = 0) )
                    anno.up <- suppressWarnings( resize(x = anno.up, width = windowsize, fix = 'start') )
                    ind <- findOverlaps(anno.up, data.category)
                    overlaps.rc.meth.lvl[context, category, as.character(i1), 'mean', 'upstream'] <- mean(data.category$rc.meth.lvl[ind@to], na.rm=TRUE)
                    overlaps.rc.meth.lvl[context, category, as.character(i1), 'weight', 'upstream'] <- length(ind@to) / sum(as.numeric(width(anno.up)))
                    overlaps.meth.lvl[context, category, as.character(i1), 'mean', 'upstream'] <- mean(data.category$meth.lvl[ind@to], na.rm=TRUE)
                    overlaps.meth.lvl[context, category, as.character(i1), 'weight', 'upstream'] <- length(ind@to) / sum(as.numeric(width(anno.up)))
                }
                for (i1 in 1:(range %/% windowsize)) {
                    anno.down <- suppressWarnings( promoters(x = annotation.down, upstream = 0, downstream = i1*windowsize) )
                    anno.down <- suppressWarnings( resize(x = anno.down, width = windowsize, fix = 'end') )
                    ind <- findOverlaps(anno.down, data.category)
                    overlaps.rc.meth.lvl[context, category, as.character(i1), 'mean', 'downstream'] <- mean(data.category$rc.meth.lvl[ind@to], na.rm=TRUE)
                    overlaps.rc.meth.lvl[context, category, as.character(i1), 'weight', 'downstream'] <- length(ind@to) / sum(as.numeric(width(anno.down)))
                    overlaps.meth.lvl[context, category, as.character(i1), 'mean', 'downstream'] <- mean(data.category$meth.lvl[ind@to], na.rm=TRUE)
                    overlaps.meth.lvl[context, category, as.character(i1), 'weight', 'downstream'] <- length(ind@to) / sum(as.numeric(width(anno.down)))
                }
            }
        }
    
        ## Inside annotation
        ioverlaps.rc.meth.lvl <- array(NA, dim=c(length(levels(data$context)), length(categories), insidewindows, 2, 1), dimnames=list(context=levels(data$context), category=categories, distance=1:insidewindows, what=c('mean', 'weight'), where=c('inside')))
        ioverlaps.meth.lvl <- array(NA, dim=c(length(levels(data$context)), length(categories), insidewindows, 2, 1), dimnames=list(context=levels(data$context), category=categories, distance=1:insidewindows, what=c('mean', 'weight'), where=c('inside')))
        ioverlaps.status.Methylated <- array(NA, dim=c(length(levels(data$context)), length(categories), insidewindows, 2, 1), dimnames=list(context=levels(data$context), category=categories, distance=1:insidewindows, what=c('mean', 'weight'), where=c('inside')))
        ioverlaps.status.Intermediate <- array(NA, dim=c(length(levels(data$context)), length(categories), insidewindows, 2, 1), dimnames=list(context=levels(data$context), category=categories, distance=1:insidewindows, what=c('mean', 'weight'), where=c('inside')))
        mask.plus <- as.logical(strand(annotation) == '+' | strand(annotation) == '*')
        mask.minus <- !mask.plus
        widths <- width(annotation)
        for (context in levels(data$context)) {
            message("Inside counts for context ", context)
            data.context <- data[data$context == context]
            for (category in categories) {
                message("  category ", category)
                if (!is.null(category.column)) {
                    data.category <- data.context[mcols(data.context)[,category.column] == category]
                } else {
                    data.category <- data.context
                }
                for (i1 in 1:insidewindows) {
                    anno.in <- annotation
                    end(anno.in[mask.plus]) <- start(annotation[mask.plus]) + round(widths[mask.plus] * i1 / insidewindows)
                    start(anno.in[mask.plus]) <- start(annotation[mask.plus]) + round(widths[mask.plus] * (i1-1) / insidewindows)
                    start(anno.in[mask.minus]) <- end(annotation[mask.minus]) - round(widths[mask.minus] * i1 / insidewindows)
                    end(anno.in[mask.minus]) <- end(annotation[mask.minus]) - round(widths[mask.minus] * (i1-1) / insidewindows)
                    ind <- findOverlaps(anno.in, data.category)
                    ioverlaps.rc.meth.lvl[context, category, as.character(i1), 'mean', 'inside'] <- mean(data.category$rc.meth.lvl[ind@to], na.rm=TRUE)
                    ioverlaps.rc.meth.lvl[context, category, as.character(i1), 'weight', 'inside'] <- length(ind@to) / sum(as.numeric(width(anno.in)))
                    ioverlaps.meth.lvl[context, category, as.character(i1), 'mean', 'inside'] <- mean(data.category$meth.lvl[ind@to], na.rm=TRUE)
                    ioverlaps.meth.lvl[context, category, as.character(i1), 'weight', 'inside'] <- length(ind@to) / sum(as.numeric(width(anno.in)))
                    ioverlaps.status.Methylated[context, category, as.character(i1), 'mean', 'inside'] <- mean(data.category$status[ind@to] == "Methylated", na.rm=TRUE)
                    ioverlaps.status.Methylated[context, category, as.character(i1), 'weight', 'inside'] <- length(ind@to) / sum(as.numeric(width(anno.in)))
                    ioverlaps.status.Intermediate[context, category, as.character(i1), 'mean', 'inside'] <- mean(data.category$status[ind@to] == "Intermediate", na.rm=TRUE)
                    ioverlaps.status.Intermediate[context, category, as.character(i1), 'weight', 'inside'] <- length(ind@to) / sum(as.numeric(width(anno.in)))
                }
            }
        }
        
        overlaps.list <- list(meth.lvl = overlaps.meth.lvl, rc.meth.lvl = overlaps.rc.meth.lvl)
        ioverlaps.list <- list(meth.lvl = ioverlaps.meth.lvl, rc.meth.lvl = ioverlaps.rc.meth.lvl)
        
        df.list <- list()
        for (i1 in 1:length(overlaps.list)) {
            name <- names(overlaps.list)[i1]
            overlaps <- overlaps.list[[name]]
            ioverlaps <- ioverlaps.list[[name]]
            
            ## Normalize weight over categories
            overlaps[,,,what='weight',] <- sweep(x = overlaps[,,,what='weight',, drop=FALSE], MARGIN = c(1,3,4,5), STATS = apply(overlaps[,,,what='weight',, drop=FALSE], c(1,3,4,5), sum), FUN = '/')
            ioverlaps[,,,what='weight',] <- sweep(x = ioverlaps[,,,what='weight',, drop=FALSE], MARGIN = c(1,3,4,5), STATS = apply(ioverlaps[,,,what='weight',, drop=FALSE], c(1,3,4,5), sum), FUN = '/')
            
            ## Prepare data.frames for plotting
            dfo <- reshape2::melt(overlaps)
            df <- dfo[dfo$what == 'mean',]
            names(df)[6] <- 'mean'
            df$weight <- dfo$value[dfo$what == 'weight']
            df$distance <- as.numeric(df$distance)
            # Adjust distances for plot
            df$distance[df$where == 'upstream'] <- -df$distance[df$where == 'upstream'] * windowsize
            df$distance[df$where == 'downstream'] <- (df$distance[df$where == 'downstream']-1) * windowsize + range
            
            dfo <- reshape2::melt(ioverlaps)
            idf <- dfo[dfo$what == 'mean',]
            names(idf)[6] <- 'mean'
            idf$weight <- dfo$value[dfo$what == 'weight']
            idf$distance <- as.numeric(idf$distance)
            # Adjust distances for plot
            idf$distance <- (idf$distance-1) * range / insidewindows
            
            df.list[[name]] <- rbind(df, idf)
        }
    }
    
    if (!plot) {
        return(df.list)
    }
    
    plotlist <- list()
    for (i1 in 1:length(df.list)) {
        name <- names(df.list)[i1]
        df <- df.list[[name]]
        
        breaks <- c(c(-1, -0.5, 0, 0.5, 1, 1.5, 2) * range)
        labels <- c(-range, -range/2, '0%', '50%', '100%', range/2, range)
        ylabs <- c('Mean methylation\nlevel', 'Mean recalibrated\nmethylation level')
            
        ggplts <- list()
        # Enrichment profile
        ggplt <- ggplot(df) + geom_line(aes_string(x='distance', y='mean', col='context'))
        ggplt <- ggplt + scale_x_continuous(breaks=breaks, labels=labels)
        ggplt <- ggplt + scale_y_continuous(limits=c(0,1))
        ggplt <- ggplt + xlab('Distance from annotation')
        ggplt <- ggplt + ylab(ylabs[i1])
        if (!is.null(category.column)) {
            ggplt <- ggplt + facet_grid(.~category)
        }
        ggplt <- ggplt + theme_bw()
        ggplts[['profile']] <- ggplt
        plotlist[[name]] <- ggplt
        
        # # Cytosine density
        # ggplt <- ggplot(df) + geom_line(aes_string(x='distance', y='weight', col='context'))
        # ggplt <- ggplt + scale_x_continuous(breaks=breaks, labels=labels)
        # ggplt <- ggplt + xlab('Distance from annotation') + ylab('Normalized C frequency\nper bp of annotation')
        # if (!is.null(category.column)) {
        #     ggplt <- ggplt + facet_grid(.~category)
        # }
        # ggplts[['weight']] <- ggplt
        
        # cowplt <- cowplot::plot_grid(plotlist = ggplts, align = 'v', nrow=2, rel_heights=c(2,1))
        # plotlist[[name]] <- cowplt
    }

    if (plot) {
        return(plotlist)
    }
}


plotTransitionDistances <- function(model) {

    df <- as.data.frame(mcols(model$data)[c('transitionContext', 'distance')])
    df <- df[!is.na(df$transitionContext),]
    ggplt <- ggplot(df) + geom_histogram(aes_string(x='distance', y='..density..'), binwidth=1, fill='white', col='black') + theme_bw()
    ggplt <- ggplt + facet_wrap(~transitionContext, ncol = length(levels(model$data$context)))
    return(ggplt)

}


#' @describeIn plotting Maximum posterior vs. distance to nearest covered cytosine.
#' @param max.coverage.y Maximum coverage for positions on the y-axis.
#' @param min.coverage.x Minimum coverage for positions on the x-axis.
#' @param xmax Upper limit for the x-axis.
#' @param xbreaks.interval Interval for breaks on the x-axis.
#' @param cutoffs A vector with values that are plotted as horizontal lines. The names of the vector must match the context levels in \code{data$context}.
#' @export
plotPosteriorDistance <- function(model, datapoints=1e6, binwidth=5, max.coverage.y=0, min.coverage.x=3, xmax=200, xbreaks.interval=xmax/10, cutoffs=NULL) {

    if (class(model) == 'methimputeBinomialHMM') {
        data <- model$data
    } else if (class(model) == 'GRanges') {
        data <- model
    } else {
        stop("Argument 'model' needs to be of class 'GRanges' or 'methimputeBinomialHMM'.")
    }
    if (!is.null(cutoffs)) {
        if (length(setdiff(levels(data$context), names(cutoffs))) > 0 ) {
            stop("names(cutoffs) must be equal to levels(data$context)")
        }
    }
    ptm <- startTimedMessage("Plotting maximum posterior vs. distance to nearest covered ...")
    if (length(data) > datapoints) {
        data.small <- data[sort(sample(length(data), datapoints))]
    } else {
        data.small <- data
    }
    datac <- data.small[data.small$counts[,'total'] <= max.coverage.y]
    # Distance of nearest covered cytosine
    cov <- data[data$counts[,'total'] >= min.coverage.x]
    near <- distanceToNearest(datac, cov)
    datac$distance.nearest <- NA
    datac$distance.nearest[near@from] <- mcols(near)$distance
    # Plot
    df <- data.frame(posteriorMax=datac$posteriorMax, distance.nearest=datac$distance.nearest, context=datac$context)
    df$distance.nearest <- df$distance.nearest %/% binwidth * binwidth
    df$distance.nearest.factor <- factor(df$distance.nearest)
    ggplt <- ggplot(df[df$distance.nearest <= xmax,]) + geom_boxplot(aes_string(x='distance.nearest.factor', y='posteriorMax', fill='context'), outlier.shape = NA) + theme_bw()
    ggplt <- ggplt + facet_grid(.~context)
    ggplt <- ggplt + xlab(paste0('Distance in [bp] to nearest position with coverage >= ', min.coverage.x)) + ylab(paste0('Maximum posterior\nat positions with coverage <= ', max.coverage.y))
    ggplt <- ggplt + scale_x_discrete(breaks=seq(0,max(df$distance.nearest, na.rm=TRUE), by=xbreaks.interval))
    if (!is.null(cutoffs)) {
        df <- data.frame(context=names(cutoffs), cutoff=cutoffs)
        ggplt <- ggplt + geom_hline(data=df, mapping=aes_string(yintercept='cutoff'), linetype=1)
    }
    ggplt <- ggplt + ggtitle('Confidence vs. distance')
    stopTimedMessage(ptm)
    return(ggplt)
}


#' #' Plot a count histogram
#' #'
#' #' Plot a histogram of count values and fitted distributions.
#' #'
#' #' @importFrom stats dnbinom
#' plotHistogram2 <- function(model, binwidth=10) {
#' 
#'     ## Assign variables
#'     counts <- model$data$observable
#'     maxcounts <- max(counts)
#' 
#'     ## Plot histogram
#'     ggplt <- ggplot(data.frame(counts)) + geom_histogram(aes_string(x='counts', y='..density..'), binwidth=binwidth, color='black', fill='white') + xlab("counts")
#'     ggplt <- ggplt + coord_cartesian(xlim=c(0,quantile(counts, 0.995)))
#'     ggplt <- ggplt + theme_bw()
#' 
#'     ## Add distributions
#'     if (!is.null(model$params$emissionParams)) {
#'         x <- seq(0, maxcounts, by = binwidth)
#'         distr <- list(x=x)
#'         for (irow in 1:nrow(model$params$emissionParams)) {
#'             e <- model$params$emissionParams
#'             if (e$type[irow] == 'delta') {
#'                 distr[[rownames(model$params$emissionParams)[irow]]] <- rep(0, length(x))
#'                 distr[[rownames(model$params$emissionParams)[irow]]][1] <- model$params$weights[irow]
#'             } else if (e$type[irow] == 'dnbinom') {
#'                 distr[[rownames(model$params$emissionParams)[irow]]] <- model$params$weights[irow] * stats::dnbinom(x, size=e[irow,'size'], prob=e[irow,'prob'])
#'             }
#'         }
#'         distr <- as.data.frame(distr)
#'         distr$Total <- rowSums(distr[,2:(1+nrow(model$params$emissionParams))])
#'         distr <- reshape2::melt(distr, id.vars='x', variable.name='components')
#'         distr$components <- sub('^X', '', distr$components)
#'         distr$components <- factor(distr$components, levels=c(levels(model$data$state), 'Total'))
#'         ggplt <- ggplt + geom_line(data=distr, mapping=aes_string(x='x', y='value', col='components'))
#' 
#'         ## Make legend
#'         lmeans <- round(model$params$emissionParams[,'mu'], 2)
#'         lvars <- round(model$params$emissionParams[,'var'], 2)
#'         lweights <- round(model$params$weights, 2)
#'         legend <- paste0(rownames(model$params$emissionParams), ", mean=", lmeans, ", var=", lvars, ", weight=", lweights)
#'         legend <- c(legend, paste0('Total, mean=', round(mean(counts),2), ', var=', round(var(counts),2)))
#'         ggplt <- ggplt + scale_color_manual(name="components", values=getStateColors(c(rownames(model$params$emissionParams),'Total')), labels=legend) + theme(legend.position=c(1,1), legend.justification=c(1,1))
#'     }
#' 
#'     return(ggplt)
#' }
#' 
#' 
#' plotBoxplot <- function(model, datapoints=1000) {
#'   
#'     df <- data.frame(state=model$data$state, observable=model$data$observable)
#'     if (datapoints < nrow(df)) {
#'         df <- df[sample(1:nrow(df), datapoints, replace = FALSE), ]
#'     }
#'     df <- suppressMessages( reshape2::melt(df) )
#'     names(df) <- c('state', 'status', 'observable')
#'     ggplt <- ggplot(df) + geom_boxplot(aes_string(x='state', y='observable', fill='status'))
#'     return(ggplt)
#'     
#' }

#' #' Histograms faceted by state
#' #' 
#' #' Make histograms of variables in \code{bins} faceted by state in \code{segmentation}.
#' #' 
#' #' @param segmentation A segmentation with metadata column 'state'.
#' #' @param bins A \code{\link{binnedMethylome}}.
#' #' @param plotcol A character vector specifying the meta-data columns for which to produce the faceted plot.
#' #' @param binwidth Bin width for the histogram.
#' #' @return A \code{\link[ggplot2]{ggplot}}.
#' #' @importFrom reshape2 melt
#' plotStateHistograms <- function(segmentation, bins, plotcol, binwidth) {
#'   
#'     states <- levels(segmentation$state)
#'     segmentation.split <- split(segmentation, segmentation$state)
#'     mind <- findOverlaps(bins, segmentation.split, select='first')
#'     bins$state <- factor(names(segmentation.split)[mind], levels=states)
#'     
#'     df <- data.frame(state=bins$state, mcols(bins)[,plotcol])
#'     names(df)[2:ncol(df)] <- plotcol
#'     dfm <- reshape2::melt(df, id.vars = 'state', measure.vars = plotcol, variable.name = 'plotcol')
#'     ggplt <- ggplot(dfm) + geom_freqpoly(aes_string(x='value', y='..density..', col='plotcol'), binwidth = binwidth)
#'     ggplt <- ggplt + theme_bw()
#'     ggplt <- ggplt + facet_wrap(~ state)
#'     
#'     return(ggplt)
#' }


#' #' Scatter plots faceted by state
#' #' 
#' #' Make scatter plots of two variables in \code{bins} faceted by state in \code{segmentation}.
#' #' 
#' #' @param segmentation A segmentation with metadata column 'state'.
#' #' @param bins A \code{\link{binnedMethylome}}.
#' #' @param x A character specifying the meta-data column that should go on the x-axis.
#' #' @param y A character specifying the meta-data column that should go on the y-axis.
#' #' @param col A character specifying the meta-data column that should be used for coloring.
#' #' @return A \code{\link[ggplot2]{ggplot}}.
#' plotStateScatter <- function(segmentation, bins, x, y, col=NULL, datapoints=1000) {
#'   
#'     states <- levels(segmentation$state)
#'     segmentation.split <- split(segmentation, segmentation$state)
#'     mind <- findOverlaps(bins, segmentation.split, select='first')
#'     bins$seg.state <- factor(names(segmentation.split)[mind], levels=states)
#'     
#'     df <- data.frame(state = bins$seg.state, x = mcols(bins)[,x], y = mcols(bins)[,y], color=mcols(bins)[,col])
#'     df <- df[sample(1:nrow(df), size=datapoints, replace=FALSE),]
#'     if (!is.null(col)) {
#'         ggplt <- ggplot(df) + geom_jitter(aes_string(x='x', y='y', col='color'), alpha=0.1)
#'     } else {
#'         ggplt <- ggplot(df) + geom_jitter(aes_string(x='x', y='y'), alpha=0.1)
#'     }
#'     ggplt <- ggplt + theme_bw()
#'     ggplt <- ggplt + xlab(x) + ylab(y)
#'     ggplt <- ggplt + facet_wrap(~ state)
#'     ggplt <- ggplt + scale_color_manual(values=getDistinctColors(levels(df$color)))
#'     
#'     return(ggplt)
#' }









#' #' @describeIn enrichment_analysis Compute the fold enrichment of combinatorial states for multiple annotations.
#' #' @param model A \code{\link{combinedMultimodel}} or \code{\link{multimodel}} object or a file that contains such an object.
#' #' @param annotations A \code{list()} with \code{\link{GRanges}} objects containing coordinates of multiple annotations The names of the list entries will be used to name the return values.
#' #' @param plot A logical indicating whether the plot or an array with the fold enrichment values is returned.
#' #' @param logscale Whether (\code{TRUE}) or not (\code{FALSE}) to plot on log scale.
#' #' @param cluster Whether (\code{TRUE}) or not (\code{FALSE}) to cluster the annotations.
#' #' @importFrom S4Vectors subjectHits queryHits
#' #' @importFrom IRanges subsetByOverlaps
#' #' @importFrom reshape2 melt
#' #' @importFrom stats hclust as.dendrogram
#' #' @export
#' heatmapEnrichment <- function(model, annotations, plot=TRUE, logscale=TRUE, cluster=TRUE) {
#'   
#'   ## Variables
#'   bins <- model$data
#'   genome <- sum(as.numeric(width(bins)))
#'   annotationsAtBins <- lapply(annotations, function(x) { IRanges::subsetByOverlaps(x, bins) })
#'   feature.lengths <- lapply(annotationsAtBins, function(x) { sum(as.numeric(width(x))) })
#'   state.levels <- levels(bins$state)
#'   # Only state levels that actually appear
#'   state.levels <- state.levels[state.levels %in% unique(bins$state)]
#'   
#'   ggplts <- list()
#'   folds <- list()
#'   maxfolds <- list()
#'   
#'   ptm <- startTimedMessage("Calculating fold enrichment ...")
#'   fold <- array(NA, dim=c(length(annotationsAtBins), length(state.levels)), dimnames=list(annotation=names(annotationsAtBins), state=state.levels))
#'   for (istate in 1:length(state.levels)) {
#'     mask <- bins$state == state.levels[istate]
#'     bins.mask <- bins[mask]
#'     state.length <- sum(as.numeric(width(bins.mask)))
#'     for (ifeat in 1:length(annotationsAtBins)) {
#'       feature <- annotationsAtBins[[ifeat]]
#'       ind <- findOverlaps(bins.mask, feature)
#'       
#'       binsinfeature <- bins.mask[unique(S4Vectors::queryHits(ind))]
#'       sum.binsinfeature <- sum(as.numeric(width(binsinfeature)))
#'       
#'       featuresinbins <- feature[unique(S4Vectors::subjectHits(ind))]
#'       sum.featuresinbins <- sum(as.numeric(width(featuresinbins)))
#'       
#'       fold[ifeat,istate] <- sum.binsinfeature / state.length / feature.lengths[[ifeat]] * genome
#'     }
#'   }
#'   stopTimedMessage(ptm)
#'   
#'   ## Clustering
#'   if (cluster) {
#'     hc.anno <- stats::hclust(dist(fold))
#'     fold <- fold[hc.anno$order, ]
#'   }
#'   
#'   if (plot) {
#'     df <- reshape2::melt(fold, value.name='fold')
#'     if (logscale) {
#'       df$fold <- log(df$fold)
#'     }
#'     df$state <- factor(df$state, levels=colnames(fold))
#'     # Transform annotation to numeric for compatibility with the dendrogram
#'     df$ylabel <- df$annotation
#'     df$annotation <- as.numeric(df$annotation)
#'     maxfold <- max(df$fold, na.rm=TRUE)
#'     minfold <- max(df$fold, na.rm=TRUE)
#'     limits <- max(abs(maxfold), abs(minfold))
#'     ggplt <- ggplot(df) + geom_tile(aes_string(x='state', y='annotation', fill='fold'))
#'     ggplt <- ggplt + scale_y_continuous(breaks=1:length(unique(df$annotation)), labels=unique(df$ylabel), position='right')
#'     ggplt <- ggplt + theme_bw()
#'     ggplt <- ggplt + theme(axis.text.x = element_text(angle=90, hjust=1, vjust=0.5))
#'     if (logscale) {
#'       ggplt <- ggplt + scale_fill_gradientn(name='log(enrichment)', colors=grDevices::colorRampPalette(c("blue","white","red"))(20), values=c(seq(-limits,0,length.out=10), seq(0,limits,length.out=10)), rescaler=function(x,...) {x}, oob=identity, limits=c(-limits,limits), na.value="blue")
#'     } else {
#'       ggplt <- ggplt + scale_fill_gradientn(name='enrichment', colors=grDevices::colorRampPalette(c("blue","white","red"))(20), values=c(seq(0,1,length.out=10), seq(1,maxfold,length.out=10)), rescaler=function(x,...) {x}, oob=identity, limits=c(0,maxfold))
#'     }
#'     cowplt <- ggplt
#'     ## Dendrograms
#'     if (cluster) {
#'       theme_none <- theme(axis.text = element_blank(),
#'                           axis.ticks = element_blank(),
#'                           panel.background = element_blank(),
#'                           axis.title = element_blank())
#'       # Row dendrogram
#'       df.dendro <- ggdendro::segment(ggdendro::dendro_data(stats::as.dendrogram(hc.anno)))
#'       row.dendro <- ggplot(df.dendro) +  geom_segment(aes_string(x='y', y='x', xend='yend', yend='xend')) +  theme_none + scale_x_reverse() + coord_cartesian(ylim=c(0.5,max(df$annotation)+0.5))
#'       # Column dendrogram
#'       # col.dendro <- ggplot(ggdendro::segment(ggdendro::dendro_data(stats::as.dendrogram(hc.state)))) +  geom_segment(aes_string(x='x', y='y', xend='xend', yend='yend')) + theme_none
#'       cowplt <- cowplot::plot_grid(row.dendro, ggplt, align = 'h', ncol = 2, rel_widths = c(1,3))
#'     }
#'     return(cowplt)
#'   } else {
#'     return(fold)
#'   }
#' }