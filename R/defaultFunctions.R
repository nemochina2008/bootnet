# Principal direction (multiplies columns with sign of first eigenvector correlations):
principalDirection <- function(corMat){
  ev <- eigen(corMat)
  ev1 <- sign(ev$vectors[,1])
  corMat <- corMat * outer(ev1, ev1)
  return(corMat)
}

principalDirection_noCor <- function(data){
  corMat <- cor(data, use = "pairwise.complete.obs")
  ev <- eigen(corMat)
  ev1 <- sign(ev$vectors[,1])
  for (i in 1:ncol(data)){
    data[,i] <-  data[,i] * ev1[i]
  }
  return(data)
}

# Folling R:
mgm <- NULL
mgmfit <- NULL

# Null function:
null <- function(...) NULL

### IsingFit ###
# prep fun (make binary if needed):
binarize <- function(x, split = "median", na.rm=TRUE, removeNArows = TRUE, verbose = TRUE){
  x <- as.data.frame(x)
  
  if (all(unlist(x) %in% c(0,1))){
    return(x)
  } else {
    
    if (is.function(split)){
      splitName <- deparse(substitute(split))
    } else {
      splitName <- split
    }
    if (verbose){
      warning(paste("Splitting data by",splitName))
    }
    
    if (is.character(split) || is.function(split)){
      splits <- sapply(x,split,na.rm=na.rm)      
    } else {
      splits <- rep(split, length=ncol(x))
    }
    for (i in seq_len(ncol(x))){
      x[,i] <- 1 * (x[,i] < splits[i])
    }
    
    if (removeNArows){
      x <- x[apply(x,1,function(xx)all(!is.na(xx))),,drop=FALSE]
    }
    
    return(x)
  }
}


### ARGUMENT ESTIMATOR ###
# Construct the estimator:
bootnet_argEstimator <- function(data, prepFun, prepArgs, estFun, estArgs, graphFun, graphArgs, intFun, intArgs, verbose = TRUE){
  # prepArgs$verbose <- verbose
  if ("verbose" %in% names(formals(prepFun))){
    prepArgs$verbose <- verbose
  }
  
  # Compute input:
  input <- do.call(prepFun, c(list(data), prepArgs))
  
  # Compute network:
  res <- do.call(estFun, c(list(input),estArgs))
  
  # Extract network:
  sampleGraph <- do.call(graphFun,c(list(res), graphArgs))
  
  # Extract graph:
  intercepts <-  do.call(intFun,c(list(res), intArgs))
  
  # Return:
  return(list(graph=sampleGraph, intercepts = intercepts))
}

### EBIC GLASSO ESTIMATOR ###
bootnet_EBICglasso <- function(
  data, # Dataset used
  tuning = 0.5, # tuning parameter
  corMethod = c("cor_auto","cov","cor","npn"), # Correlation method
  missing = c("pairwise","listwise","fiml","stop"),
  sampleSize = c("maximum","minimim"), # Sample size when using missing = "pairwise"
  verbose = TRUE,
  corArgs = list(), # Extra arguments to the correlation function
  refit = FALSE,
  principalDirection = FALSE,
  lambda.min.ratio = 0.01,
  nlambda = 100,
  threshold = FALSE,
  ...
){
  # Check arguments:
  corMethod <- match.arg(corMethod)
  missing <- match.arg(missing)
  sampleSize <- match.arg(sampleSize)
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - qgraph::EBICglasso for EBIC model selection\n    - using glasso::glasso")
    if (corMethod == "cor_auto"){
      msg <- paste0(msg,"\n  - qgraph::cor_auto for correlation computation\n    - using lavaan::lavCor")
    }
    if (corMethod == "npn"){
      msg <- paste0(msg,"\n  - huge::huge.npn for nonparanormal transformation")
    }
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  }
  
  # Correlate data:
  # npn:
  if (corMethod == "npn"){
    data <- huge::huge.npn(data)
    corMethod <- "cor"
  }
  
  # cor_auto:
  if (corMethod == "cor_auto"){
    args <- list(data=data,missing=missing,verbose=verbose)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    corMat <- do.call(qgraph::cor_auto,args)
  } else if (corMethod%in%c("cor","cov")){
    # Normal correlations
    if (missing == "fiml"){
      stop("missing = 'fiml' only supported with corMethod = 'cor_auto'")
    }
    use <- switch(missing,
                  pairwise = "pairwise.complete.obs",
                  listwise = "complete.obs")
    
    args <- list(x=data,use=use)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    
    corMat <- do.call(corMethod,args)
  } else stop ("Correlation method is not supported.")
  
  # Sample size:
  if (missing == "listwise"){
    sampleSize <- nrow(na.omit(data))
  } else{
    if (sampleSize == "maximum"){
      sampleSize <- sum(apply(data,1,function(x)!all(is.na(x))))
    } else {
      sampleSize <- sum(apply(data,1,function(x)!any(is.na(x))))
    }
  } 
  
  # Principal direction:
  if (principalDirection){
    corMat <- principalDirection(corMat)
  }
  
  # Estimate network:
  Results <- qgraph::EBICglasso(corMat,
                                n =  sampleSize, 
                                gamma = tuning,
                                returnAllResults = TRUE,
                                refit = refit,
                                lambda.min.ratio=lambda.min.ratio,
                                nlambda = nlambda,
                                threshold=threshold,
                                ...)
  
  # Return:
  return(list(graph=Results$optnet,results=Results))
}



### EBIC GLASSO 2 ESTIMATOR ###
bootnet_ggmModSelect <- function(
  data, # Dataset used
  tuning = 0, # tuning parameter
  corMethod = c("cor_auto","cov","cor","npn"), # Correlation method
  missing = c("pairwise","listwise","fiml","stop"),
  sampleSize = c("maximum","minimim"), # Sample size when using missing = "pairwise"
  verbose = TRUE,
  corArgs = list(), # Extra arguments to the correlation function
  principalDirection = FALSE,
  start = c("glasso","empty","full"),
  stepwise = TRUE,
  nCores = 1,
  ...
){
  # Check arguments:
  corMethod <- match.arg(corMethod)
  missing <- match.arg(missing)
  sampleSize <- match.arg(sampleSize)
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - qgraph::ggmModSelect for model selection\n    - using glasso::glasso")
    if (corMethod == "cor_auto"){
      msg <- paste0(msg,"\n  - qgraph::cor_auto for correlation computation\n    - using lavaan::lavCor")
    }
    if (corMethod == "npn"){
      msg <- paste0(msg,"\n  - huge::huge.npn for nonparanormal transformation")
    }
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  }
  
  # Correlate data:
  # npn:
  if (corMethod == "npn"){
    data <- huge::huge.npn(data)
    corMethod <- "cor"
  }
  
  # cor_auto:
  if (corMethod == "cor_auto"){
    args <- list(data=data,missing=missing,verbose=verbose)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    corMat <- do.call(qgraph::cor_auto,args)
  } else if (corMethod%in%c("cor","cov")){
    # Normal correlations
    if (missing == "fiml"){
      stop("missing = 'fiml' only supported with corMethod = 'cor_auto'")
    }
    use <- switch(missing,
                  pairwise = "pairwise.complete.obs",
                  listwise = "complete.obs")
    
    args <- list(x=data,use=use)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    
    corMat <- do.call(corMethod,args)
  } else stop ("Correlation method is not supported.")
  
  # Sample size:
  if (missing == "listwise"){
    sampleSize <- nrow(na.omit(data))
  } else{
    if (sampleSize == "maximum"){
      sampleSize <- sum(apply(data,1,function(x)!all(is.na(x))))
    } else {
      sampleSize <- sum(apply(data,1,function(x)!any(is.na(x))))
    }
  } 
  
  # Principal direction:
  if (principalDirection){
    corMat <- principalDirection(corMat)
  }
  
  # Estimate network:
  Results <- qgraph::ggmModSelect(corMat,
                                n =  sampleSize, 
                                gamma = tuning,
                                start = start,
                                stepwise = stepwise,
                                verbose = verbose,
                                nCores = 1,
                                ...)
  # Return:
  return(list(graph=as.matrix(Results$graph),results=Results))
}

### PCOR ESTIMATOR ###
bootnet_pcor <- function(
  data, # Dataset used
  corMethod = c("cor_auto","cov","cor","npn"), # Correlation method
  missing = c("pairwise","listwise","fiml","stop"),
  sampleSize = c("maximum","minimim"), # Sample size when using missing = "pairwise"
  verbose = TRUE,
  corArgs = list(), # Extra arguments to the correlation function
  threshold = 0,
  alpha = 0.05,
  principalDirection = FALSE
){
  # Check arguments:
  corMethod <- match.arg(corMethod)
  missing <- match.arg(missing)
  sampleSize <- match.arg(sampleSize)
  
  if (identical(threshold,"none")){
    threshold <- 0
  }
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - qgraph::qgraph(..., graph = 'pcor') for network computation")
    if (corMethod == "cor_auto"){
      msg <- paste0(msg,"\n  - qgraph::cor_auto for correlation computation\n    - using lavaan::lavCor")
    }
    if (corMethod == "npn"){
      msg <- paste0(msg,"\n  - huge::huge.npn for nonparanormal transformation")
    }
    if (threshold != "none"){
      if (threshold != "locfdr"){
        msg <- paste0(msg,"\n  - psych::corr.p for significance thresholding")        
      } else {
        msg <- paste0(msg,"\n  - fdrtool for false discovery rate")        
      }

    }
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  }
  
  # Correlate data:
  # npn:
  if (corMethod == "npn"){
    data <- huge::huge.npn(data)
    corMethod <- "cor"
  }
  
  # cor_auto:
  if (corMethod == "cor_auto"){
    args <- list(data=data,missing=missing,verbose=verbose)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    corMat <- do.call(qgraph::cor_auto,args)
  } else if (corMethod%in%c("cor","cov")){
    # Normal correlations
    if (missing == "fiml"){
      stop("missing = 'fiml' only supported with corMethod = 'cor_auto'")
    }
    use <- switch(missing,
                  pairwise = "pairwise.complete.obs",
                  listwise = "complete.obs")
    
    args <- list(x=data,use=use)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    
    corMat <- do.call(corMethod,args)
  } else stop ("Correlation method is not supported.")
  
  # Sample size:
  if (missing == "listwise"){
    sampleSize <- nrow(na.omit(data))
  } else{
    if (sampleSize == "maximum"){
      sampleSize <- sum(apply(data,1,function(x)!all(is.na(x))))
    } else {
      sampleSize <- sum(apply(data,1,function(x)!any(is.na(x))))
    }
  } 
  
  # Principal direction:
  if (principalDirection){
    corMat <- principalDirection(corMat)
  }
  
  # Estimate network:
  Results <- getWmat(qgraph::qgraph(corMat,graph = "pcor",DoNotPlot = TRUE,threshold=threshold,alpha=alpha, sampleSize = sampleSize))
  
  # Return:
  return(list(graph=Results,results=Results))
}


### COR ESTIMATOR ###
bootnet_cor <- function(
  data, # Dataset used
  corMethod = c("cor_auto","cov","cor","npn"), # Correlation method
  missing = c("pairwise","listwise","fiml","stop"),
  sampleSize = c("maximum","minimim"), # Sample size when using missing = "pairwise"
  verbose = TRUE,
  corArgs = list(), # Extra arguments to the correlation function
  threshold = 0,
  alpha = 0.05,
  principalDirection = FALSE
){
  # Check arguments:
  corMethod <- match.arg(corMethod)
  missing <- match.arg(missing)
  sampleSize <- match.arg(sampleSize)
  
  if (identical(threshold,"none")){
    threshold <- 0
  }
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    # msg <- paste0(msg,"\n  - qgraph::qgraph(..., graph = 'cor') for network computation")
    if (corMethod == "cor_auto"){
      msg <- paste0(msg,"\n  - qgraph::cor_auto for correlation computation\n    - using lavaan::lavCor")
    }
    if (corMethod == "npn"){
      msg <- paste0(msg,"\n  - huge::huge.npn for nonparanormal transformation")
    }
    if (threshold != "none"){
      if (threshold != "locfdr"){
        msg <- paste0(msg,"\n  - psych::corr.p for significance thresholding")        
      } else {
        msg <- paste0(msg,"\n  - fdrtool for false discovery rate")        
      }
      
    }
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  }
  
  # Correlate data:
  # npn:
  if (corMethod == "npn"){
    data <- huge::huge.npn(data)
    corMethod <- "cor"
  }
  
  # cor_auto:
  if (corMethod == "cor_auto"){
    args <- list(data=data,missing=missing,verbose=verbose)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    corMat <- do.call(qgraph::cor_auto,args)
  } else if (corMethod%in%c("cor","cov")){
    # Normal correlations
    if (missing == "fiml"){
      stop("missing = 'fiml' only supported with corMethod = 'cor_auto'")
    }
    use <- switch(missing,
                  pairwise = "pairwise.complete.obs",
                  listwise = "complete.obs")
    
    args <- list(x=data,use=use)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    
    corMat <- do.call(corMethod,args)
  } else stop ("Correlation method is not supported.")
  
  # Sample size:
  if (missing == "listwise"){
    sampleSize <- nrow(na.omit(data))
  } else{
    if (sampleSize == "maximum"){
      sampleSize <- sum(apply(data,1,function(x)!all(is.na(x))))
    } else {
      sampleSize <- sum(apply(data,1,function(x)!any(is.na(x))))
    }
  } 
  
  # Principal direction:
  if (principalDirection){
    corMat <- principalDirection(corMat)
  }
  
  # Estimate network:
  Results <- getWmat(qgraph::qgraph(corMat,graph = "cor",DoNotPlot = TRUE,threshold=threshold, sampleSize = sampleSize, alpha=alpha))
  
  # Return:
  return(list(graph=Results,results=Results))
}


### ISINGFIT ESTIMATOR ###
bootnet_IsingFit <- function(
  data, # Dataset used
  tuning = 0.25, # tuning parameter
  missing = c("listwise","stop"),
  verbose = TRUE,
  rule = c("AND","OR"),
  split = "median",
  principalDirection = FALSE
){
  # Check arguments:
  missing <- match.arg(missing)
  rule <- match.arg(rule)
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - IsingFit::IsingFit for network computation\n    - Using glmnet::glmnet")
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  } else {
    # listwise:
    data <- na.omit(data)
  }
  
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  # Binarize:
  if (!all(data %in% c(0,1))){
    data <- bootnet::binarize(data, split = split, verbose = verbose)
  }
  
  # Principal direction:
  if (principalDirection){
    data <- principalDirection_noCor(data)
  }
  
  # Estimate network:
  Results <- IsingFit::IsingFit(data, AND = rule == "AND", gamma = tuning,progressbar = verbose,plot = FALSE)
 
  # Return:
  return(list(graph = Results$weiadj, intercepts = Results$thresholds,
              results = Results))
}

### ISINGSAMPLER ESTIMATOR ###
bootnet_IsingSampler <- function(
  data, # Dataset used
  missing = c("listwise","stop"),
  verbose = TRUE,
  split = "median",
  method = c("default","ll","pl","uni","bi"),
  principalDirection = FALSE
){
  # Check arguments:
  missing <- match.arg(missing)
  method <- match.arg(method)
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - IsingSampler::EstimateIsing for network computation")
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  if (method == "default"){
    if (ncol(data) > 20){
      method <- "uni"
      if (verbose){
        message("'method' set to 'uni'")
      }
    } else {
      method <- "ll"
      if (verbose){
        message("'method' set to 'll'")
      }
    }
  }
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  } else {
    # listwise:
    data <- na.omit(data)
  }
  
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  # Binarize:
  if (!all(data %in% c(0,1))){
    data <- bootnet::binarize(data, split = split, verbose = verbose)
  }
  
  # Principal direction:
  if (principalDirection){
    data <- principalDirection_noCor(data)
  }
  
  # Estimate network:
  Results <- IsingSampler::EstimateIsing(as.matrix(data), method = method)
  
  # Return:
  return(list(graph = Results$graph, intercepts = Results$thresholds,
              results = Results))
}


### PCOR ESTIMATOR ###
bootnet_adalasso <- function(
  data, # Dataset used
  missing = c("listwise","stop"),
  verbose = TRUE,
  nFolds = 10, # Number of folds
  principalDirection = FALSE
){
  # Check arguments:
  missing <- match.arg(missing)
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - parcor::adalasso.net for network computation")
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  } else {
    # listwise:
    data <- na.omit(data)
  }
  
  # Principal direction:
  if (principalDirection){
    data <- principalDirection_noCor(data)
  }
  
  # Estimate network:
  Results <- parcor::adalasso.net(data, k = nFolds)
  
  # Return:
  return(list(graph=as.matrix(Matrix::forceSymmetric(Results$pcor.adalasso)),results=Results))
}


### HUGE ESTIMATOR ###
bootnet_huge <- function(
  data, # Dataset used
  tuning = 0.5,
  missing = c("listwise","stop"),
  verbose = TRUE,
  npn = TRUE, # Compute nonparanormal?
  criterion = c("ebic","ric","stars"),
  principalDirection = FALSE,
  lambda.min.ratio = 0.01,
  nlambda = 100
  # method = c("glasso","mb","ct")
){
  # Check arguments:
  missing <- match.arg(missing)
  criterion <- match.arg(criterion)
  # method <- match.arg(method)
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - huge::huge for network computation")
    msg <- paste0(msg,"\n  - huge::huge.npn for nonparanormal transformation")
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  } else {
    # listwise:
    data <- na.omit(data)
  }
  
  # Nonparanormal:
  if (npn){
    data <- huge::huge.npn(na.omit(as.matrix(data)),verbose = verbose)
  }
  
  # Principal direction:
  if (principalDirection){
    data <- principalDirection_noCor(data)
  }
  
  # Estimate network:
  Results <- huge::huge.select(huge::huge(data,method = "glasso",verbose=verbose,lambda.min.ratio=lambda.min.ratio,nlambda=nlambda), criterion = criterion,verbose = verbose,ebic.gamma = tuning)
  
  # Return:
  return(list(
    graph=as.matrix(qgraph::wi2net(as.matrix(Results$opt.icov))),
    results=Results))
}

### MGM ESTIMATOR ###
bootnet_mgm <- function(
  data, # Dataset used
  type,
  level,
  tuning = 0.5,
  missing = c("listwise","stop"),
  verbose = TRUE,
  criterion = c("EBIC","CV"),
  nFolds = 10,
  order = 2,
  rule = c("AND","OR"),
  binarySign, # Detected by default
  ... # mgm functions
  # method = c("glasso","mb","ct")
){
  # Check arguments:
  missing <- match.arg(missing)
  criterion <- match.arg(criterion)
  rule <- match.arg(rule)
  # method <- match.arg(method)
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - mgm::mgm for network computation\n    - Using glmnet::glmnet")
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # # If matrix coerce to data frame:
  # if (is.matrix(data)){
  #   data <- as.data.frame(data)
  # }
  # If is not a matrix coerce to matrix (because mgm is silly):
  # if (!is.matrix(data)){
    data <- as.matrix(data)
  # }
  
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  } else {
    # listwise:
    data <- na.omit(data)
  }
  
  # Set type automatically:
  if (missing(type)){
    if (verbose){
      message("'type' argument not assigned. Setting type to 'c' for all binary variables and 'g' for all other variables.")     
    }
    type <- ifelse(apply(data,2,function(x)all(x%in%c(0,1))),"c","g")
  }
  if (length(type) != ncol(data)){
    type <- rep(type, ncol(data))
  }
  
  # Set level automatically:
  if (missing(level)){
    if (verbose){
      message("'level' argument not assigned. Setting level to 1 for all Gaussian/Poisson variables and number of unique values for all categorical variables")  
    }
    
    level <- ifelse(type == "c", apply(data,2,function(x)length(unique(x))),1)
  }
  if (length(level) != ncol(data)){
    level <- rep(level, ncol(data))
  }
  
  # Estimate:
  # mgmfun <- "mgmfit"
  # if (packageVersion("mgm") >= "1.2.0"){
  # Check if all categorical binary variables are encoded 0 and 1:
  if (missing(binarySign)){
    if (any(type == "c" & level == 2)){
      whichBinary <- which(type == "c" & level == 2)
      enc <- apply(data[,whichBinary],2,function(x)all(x[!is.na(x)]%in%c(0L,1L)))
      if (!all(enc)){
        binarySign <- FALSE
      } else {
        binarySign <- TRUE
      }
    } else {
      binarySign <- FALSE
    }
  }
  
    log <- capture.output(Results <- mgm::mgm(
      data,verbatim = !verbose,  warnings = verbose, signInfo = FALSE,
      type=type,
      level=level,
      lambdaSel = criterion,
      lambdaFolds = nFolds,
      lambdaGam = tuning,
      k = order,
      pbar = verbose,
      ruleReg = rule, saveData = FALSE, binarySign = binarySign, ...))
    
    # Warn for unsigned:
    if (any(Results$pairwise$signs==0,na.rm = TRUE)){
      warning("Bootnet does not support unsigned edges and treats these as positive edges.")
    }
    Results$pairwise$signs[is.na(Results$pairwise$signs)] <- 0
    
    # Graph:
    Graph <- Results$pairwise$wadj
    Graph <- ifelse(Results$pairwise$signs==-1,-Graph,Graph)
  #   
  # } else {
  #   log <- capture.output(Results <- do.call(mgmfun,list(
  #     data,
  #     type=type,
  #     lev=lev,
  #     lambda.sel = criterion,
  #     folds = nFolds,
  #     gam = tuning,
  #     d = degree,
  #     pbar = verbose,
  #     rule.reg = rule)))
  #   
  #   # Warn for unsigned:
  #   if (any(Results$signs==0,na.rm = TRUE)){
  #     warning("Bootnet does not support unsigned edges and treats these as positive edges.")
  #   }
  #   Results$signs[is.na(Results$signs)] <- 0
  #   
  #   # Graph:
  #   Graph <- Results$wadj
  #   Graph <- ifelse(Results$signs==-1,-Graph,Graph)
  # }

  # Return:
  return(list(
    graph=Graph,
    results=Results))
}



### RELATIVE IMPORTANCE ###
bootnet_relimp <- function(
  data, # Dataset used
  normalized = TRUE,
  type = "lmg",
  structureDefault = c("none", "custom", "EBICglasso", "pcor","IsingFit","IsingSampler", "huge","adalasso","mgm","cor","TMFG",
                       "ggmModSelect", "LoGo"),
  missing = c("listwise","stop"),
  ..., # Arguments sent to the structure function
  verbose = TRUE,
  threshold = 0
){
  nVar <- ncol(data)
  structureDefault <- match.arg(structureDefault)
  
  # Check missing:
  missing <- match.arg(missing)
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  } else {
    # listwise:
    data <- na.omit(data)
  }
  
  # Compute structure (if needed)
  if (structureDefault != "none"){
    if (verbose){
      message("Computing network structure")
      
      msg <- "Computing network structure. Using package::function:"
      if (structureDefault == "EBICglasso"){
        msg <- paste0(msg,"\n  - qgraph::EBICglasso for EBIC model selection\n    - using glasso::glasso")
      }
      if (structureDefault == "ggmModSelect"){
        msg <- paste0(msg,"\n  - qgraph::ggmModSelect for EBIC model selection\n    - using glasso::glasso")
      }
      if (structureDefault == "pcor"){
        msg <- paste0(msg,"\n  - qgraph::qgraph(..., graph = 'pcor') for network computation")
      }
      if (structureDefault == "IsingFit"){
        msg <- paste0(msg,"\n  - IsingFit::IsingFit for network computation\n    - Using glmnet::glmnet")
      }
      if (structureDefault == "IsingSampler"){
        msg <- paste0(msg,"\n  - IsingSampler::EstimateIsing for network computation")
      }
      if (structureDefault == "adalasso"){
        msg <- paste0(msg,"\n  - parcor::adalasso.net for network computation")
      }
      if (structureDefault == "huge"){
        msg <- paste0(msg,"\n  - huge::huge for network computation")
        msg <- paste0(msg,"\n  - huge::huge.npn for nonparanormal transformation")
      }
      if (structureDefault == "mgm"){
        msg <- paste0(msg,"\n  - mgm::mgm for network computation")
      }
      
      message(msg)
    }
    if (structureDefault == "custom"){
      struc <- estimateNetwork(data, ...)
    } else {
      struc <- estimateNetwork(data, default = structureDefault, ..., verbose = FALSE)
    }
    struc <- struc$graph!=0
  } else {
    struc <- matrix(TRUE, nVar,nVar)
  }
  diag(struc) <- FALSE
  
  # Empty matrix:
  relimp <- matrix(0, nVar,nVar)
  if (is.null(names(data))){
    names(data) <- paste0("V",seq_len(nVar))
  }
  Vars <- names(data)
  
  # For every node, compute incomming relative importance:
  if (verbose){
  
    msg <- "Computing relative importance network. Using package::function:\n  - relaimpo::calc.relimp for edge weight estimation"
    message(msg)
  
    pb <- txtProgressBar(0,nVar,style=3)
  }
  for (i in 1:nVar){
    if (any(struc[-i,i])){
      formula <- as.formula(paste0(Vars[i]," ~ ",paste0(Vars[-i][struc[-i,i]],collapse=" + ")))
      if (sum(struc[-i,i])==1){

        # Only one predictor
        if (normalized){
          relimp[-i,i][struc[-i,i]] <- 1
        } else {
          res <- lm(formula, data)
          sum <- summary(res)
          relimp[-i,i][struc[-i,i]] <- sum$r.squared
        }
        
      } else {
        res <- calc.relimp(formula, data, rela = normalized)
        relimp[-i,i][struc[-i,i]] <- res@lmg              
      }

    }
    if (verbose){
      setTxtProgressBar(pb, i)
    }
  }
  if (verbose){
    close(pb)
  }
  
  # threshold:
  relimp <- ifelse(relimp<threshold,0,relimp)
  
  # Return:
  return(relimp)
}


### Maximally Filtered Graph (TMFG) ###
bootnet_TMFG <- function(
  data, # Dataset used
  graphType = c("cor","pcor"),
  corMethod = c("cor_auto","cov","cor","npn"), # Correlation method
  missing = c("pairwise","listwise","fiml","stop"),
  verbose = TRUE,
  corArgs = list(), # Extra arguments to the correlation function
  principalDirection = FALSE,
  ...
){
  # Check arguments:
  corMethod <- match.arg(corMethod)
  missing <- match.arg(missing)
  
  # Message:
  if (verbose){
    if (graphType == "cor"){
      msg <- "Estimating correlation network. Using package::function:"  
    } else {
      msg <- "Estimating partial correlation network. Using package::function:" 
    }
    msg <- paste0(msg,"\n  - NetworkToolbox::TMFG for Triangulated Maximally Filtered Graph")
    if (corMethod == "cor_auto"){
      msg <- paste0(msg,"\n  - qgraph::cor_auto for correlation computation\n    - using lavaan::lavCor")
    }
    if (corMethod == "npn"){
      msg <- paste0(msg,"\n  - huge::huge.npn for nonparanormal transformation")
    }
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  }
  
  # Correlate data:
  # npn:
  if (corMethod == "npn"){
    data <- huge::huge.npn(data)
    corMethod <- "cor"
  }
  
  # cor_auto:
  if (corMethod == "cor_auto"){
    args <- list(data=data,missing=missing,verbose=verbose)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    corMat <- do.call(qgraph::cor_auto,args)
  } else if (corMethod%in%c("cor","cov")){
    # Normal correlations
    if (missing == "fiml"){
      stop("missing = 'fiml' only supported with corMethod = 'cor_auto'")
    }
    use <- switch(missing,
                  pairwise = "pairwise.complete.obs",
                  listwise = "complete.obs",
                  fiml = "fiml")
    
    args <- list(x=data,use=use)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    
    corMat <- do.call(corMethod,args)
  } else stop ("Correlation method is not supported.")
  
  # Principal direction:
  if (principalDirection){
    corMat <- principalDirection(corMat)
  }
  
  graphType <- match.arg(graphType)
  # If pcor, invert:
  if (graphType == "pcor"){
    corMat <- getWmat(qgraph(corMat, graph = "pcor", DoNotPlot=TRUE))
  }
  
  
  # Estimate network:
  Results <- NetworkToolbox::TMFG(corMat)
  
  # Return:
  return(list(graph=Results$A,results=Results))
}


### Local/Global Sparse Inverse Covariance Matrix ###
bootnet_LoGo <- function(
  data, # Dataset used
  corMethod = c("cor_auto","cov","cor","npn"), # Correlation method
  missing = c("pairwise","listwise","fiml","stop"),
  verbose = TRUE,
  corArgs = list(), # Extra arguments to the correlation function
  principalDirection = FALSE,
  ...
){
  # Check arguments:
  corMethod <- match.arg(corMethod)
  missing <- match.arg(missing)
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - NetworkToolbox::LoGo for Local/Global Sparse Inverse Covariance Matrix")
    if (corMethod == "cor_auto"){
      msg <- paste0(msg,"\n  - qgraph::cor_auto for correlation computation\n    - using lavaan::lavCor")
    }
    if (corMethod == "npn"){
      msg <- paste0(msg,"\n  - huge::huge.npn for nonparanormal transformation")
    }
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  
  # First test if data is a data frame:
  if (!(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Obtain info from data:
  N <- ncol(data)
  Np <- nrow(data)
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  }
  
  # Correlate data:
  # npn:
  if (corMethod == "npn"){
    data <- huge::huge.npn(data)
    corMethod <- "cor"
  }
  
  # cor_auto:
  if (corMethod == "cor_auto"){
    args <- list(data=data,missing=missing,verbose=verbose)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    corMat <- do.call(qgraph::cor_auto,args)
  } else if (corMethod%in%c("cor","cov")){
    # Normal correlations
    if (missing == "fiml"){
      stop("missing = 'fiml' only supported with corMethod = 'cor_auto'")
    }
    use <- switch(missing,
                  pairwise = "pairwise.complete.obs",
                  listwise = "complete.obs")
    
    args <- list(x=data,use=use)
    if (length(corArgs) > 0){
      for (i in seq_along(corArgs)){
        args[[names(corArgs)[[i]]]] <- corArgs[[i]]
      }
    }
    
    corMat <- do.call(corMethod,args)
  } else stop ("Correlation method is not supported.")
  
  # Principal direction:
  if (principalDirection){
    corMat <- principalDirection(corMat)
  }
  

  # Estimate network:
  Results <- NetworkToolbox::LoGo(corMat,normal = FALSE,partial=TRUE,standardize = TRUE,...)
  
  # Return:
  return(Results)
}


####
### graphicalVAR ESTIMATOR ###
bootnet_graphicalVAR <- function(
  data, # Dataset used
  tuning = 0.5, # tuning parameter
  verbose = TRUE,
  principalDirection = FALSE,
  missing =c("listwise","stop"),
  ...
){
  dots <- list(...)
  missing <- match.arg(missing)
  
  if (any(names(dots)=="gamma")){
    stop("Please use 'tuning' argument for EBIC hyperparameter gamma")
  }
  
  
  # Message:
  if (verbose){
    msg <- "Estimating Network. Using package::function:"  
    msg <- paste0(msg,"\n  - graphicalVAR::graphicalVAR for model estimation")
    # msg <- paste0(msg,"\n\nPlease reference accordingly\n")
    message(msg)
  }
  
  
  # First test if data is a data frame:
  if (!is(data,"tsData") && !(is.data.frame(data) || is.matrix(data))){
    stop("'data' argument must be a data frame")
  }
  
  # If matrix coerce to data frame:
  if (!is(data,"tsData") && is.matrix(data)){
    data <- as.data.frame(data)
  }
  
  # Check missing:
  if (missing == "stop"){
    if (any(is.na(data))){
      stop("Missing data detected and missing = 'stop'")
    }
  }
  
  
  # Principal direction:
  if (principalDirection){
    data <- principalDirection_noCor(data)
  }
  

  # Estimate network:
  Results <- graphicalVAR::graphicalVAR(data,...,gamma = tuning, verbose = verbose)
  
  
  # Return:
  return(list(graph=list(
    contemporaneous = Results$PCC,
    temporal = Results$PDC),
    results=Results,
    specialData = list(
      data = Results$data,
      type = "graphicalVAR"
    )))
}




