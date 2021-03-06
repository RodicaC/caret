modelInfo <- list(label = "Stochastic Gradient Boosting",
                  library = c("gbm", "plyr"),
                  type = c("Regression", "Classification"),
                  parameters = data.frame(parameter = c('n.trees', 'interaction.depth', 'shrinkage'),
                                          class = c("numeric", "numeric", "numeric"),
                                          label = c('# Boosting Iterations', 'Max Tree Depth', 'Shrinkage')),
                  grid = function(x, y, len = NULL) expand.grid(interaction.depth = seq(1, len),
                                                                n.trees = floor((1:len) * 50),
                                                                shrinkage = .1),
                  loop = function(grid) {     
                    loop <- ddply(grid, c("shrinkage", "interaction.depth"),
                                  function(x) c(n.trees = max(x$n.trees)))
                    submodels <- vector(mode = "list", length = nrow(loop))
                    for(i in seq(along = loop$n.trees))
                    {
                      index <- which(grid$interaction.depth == loop$interaction.depth[i] & 
                                       grid$shrinkage == loop$shrinkage[i])
                      trees <- grid[index, "n.trees"] 
                      submodels[[i]] <- data.frame(n.trees = trees[trees != loop$n.trees[i]])
                    }    
                    list(loop = loop, submodels = submodels)
                  },
                  fit = function(x, y, wts, param, lev, last, classProbs, ...) { 
                    ## train will figure out whether we are doing classification or reggression
                    ## from the class of the outcome and automatically specify the value of
                    ## 'distribution' in the control file. If the user wants to over-ride this,
                    ## this next bit will allow this.
                    theDots <- list(...)
                    if(any(names(theDots) == "distribution"))
                    {
                      modDist <- theDots$distribution
                      theDots$distribution <- NULL
                    } else {
                      if(is.numeric(y))
                      {
                        modDist <- "gaussian"
                      } else modDist <- if(length(lev) == 2)  "bernoulli" else "multinomial"
                    }
                    
                    ## check to see if weights were passed in (and availible)
                    if(!is.null(wts)) theDots$w <- wts     
                    if(is.factor(y) && length(lev) == 2) y <- ifelse(y == lev[1], 1, 0)
                    
                    modArgs <- list(x = x,
                                    y = y,
                                    interaction.depth = param$interaction.depth,
                                    n.trees = param$n.trees,
                                    shrinkage = param$shrinkage, 
                                    distribution = modDist)
                    
                    if(length(theDots) > 0) modArgs <- c(modArgs, theDots)
                    
                    do.call("gbm.fit", modArgs)
                  },
                  predict = function(modelFit, newdata, submodels = NULL) {
                    out <- predict(modelFit, newdata, type = "response",
                                   n.trees = modelFit$tuneValue$n.trees)
                    out[is.nan(out)] <- NA
                    
                    out <- switch(modelFit$distribution$name,
                                  multinomial = {
                                    ## The output is a 3D array that is
                                    ## nxcx1
                                    colnames(out[,,1,drop=FALSE])[apply(out[,,1,drop=FALSE], 1, which.max)]
                                  },
                                  bernoulli =, adaboost =, huberized = {
                                    ## The data come back as an nx1 vector
                                    ## of probabilities.
                                    ifelse(out >= .5, 
                                           modelFit$obsLevels[1], 
                                           modelFit$obsLevels[2])
                                  },
                                  gaussian =, laplace =, tdist =, poisson = {
                                    out
                                  })
                    
                    if(!is.null(submodels))
                    {
                      tmp <- predict(modelFit, newdata, type = "response", n.trees = submodels$n.trees)
                      out <- switch(modelFit$distribution$name,
                                    multinomial = {
                                      ## The output is a 3D array that is
                                      ## nxcx1
                                      lvl <- colnames(tmp[,,1,drop=FALSE])
                                      tmp <- apply(tmp, 3, function(x) apply(x, 1, which.max))
                                      if(is.vector(tmp)) tmp <- matrix(tmp, nrow = 1)
                                      tmp <- t(apply(tmp, 1, function(x, lvl) lvl[x], lvl = lvl))
                                      tmp <- as.list(as.data.frame(tmp, stringsAsFactors = FALSE))
                                      c(list(out), tmp)
                                    },
                                    bernoulli =, adaboost =, huberized = {
                                      ## Now we have a nxt matrix
                                      tmp <- ifelse(tmp >= .5, 
                                                    modelFit$obsLevels[1], 
                                                    modelFit$obsLevels[2])
                                      tmp <- as.list(as.data.frame(tmp, stringsAsFactors = FALSE))
                                      c(list(out), tmp)
                                    },
                                    gaussian =, laplace =, tdist =,  poisson =  {
                                      ## an nxt matrix
                                      tmp <- as.list(as.data.frame(tmp))
                                      c(list(out), tmp)
                                    })
                    }
                    out  
                  },
                  prob = function(modelFit, newdata, submodels = NULL) {
                    out <- predict(modelFit, newdata, type = "response",
                                   n.trees = modelFit$tuneValue$n.trees)
                    
                    out[is.nan(out)] <- NA
                    
                    out <- switch(modelFit$distribution$name,
                                  multinomial = {
                                    ## The output is a 3D array that is
                                    ## nxcx1
                                    out[,,1]
                                  },
                                  bernoulli =, adaboost =, huberized = {
                                    ## The data come back as an nx1 vector
                                    ## of probabilities.
                                    out <- cbind(out, 1 - out)
                                    colnames(out) <- modelFit$obsLevels
                                    out
                                  },
                                  gaussian =, laplace =, tdist =,  poisson = {
                                    out
                                  })
                    
                    if(!is.null(submodels))
                    {
                      tmp <- predict(modelFit, newdata, type = "response", n.trees = submodels$n.trees)
                      tmp <- switch(modelFit$distribution$name,
                                    multinomial = {
                                      ## The output is a 3D array that is
                                      ## nxcxt
                                      apply(tmp, 3, function(x) data.frame(x))
                                    },
                                    bernoulli =, adaboost =, huberized = {
                                      ## The data come back as an nx1t matrix
                                      ## of probabilities.
                                      tmp <- as.list(as.data.frame(tmp))
                                      lapply(tmp, function(x, lvl) {
                                        x <- cbind(x, 1 - x)
                                        colnames(x) <- lvl
                                        x
                                      }, lvl = modelFit$obsLevels)
                                    })
                      out <- c(list(out), tmp)
                    }
                    out
                  },
                  predictors = function(x, ...) {
                    vi <- relative.influence(x, n.trees = x$tuneValue$n.trees)
                    names(vi)[vi > 0]
                  },
                  varImp = function(object, numTrees = NULL, ...) {
                    if(is.null(numTrees)) numTrees <- object$tuneValue$n.trees
                    varImp <- relative.influence(object, n.trees = numTrees)
                    out <- data.frame(varImp)
                    colnames(out) <- "Overall"
                    rownames(out) <- object$var.names
                    out   
                  },
                  levels = function(x) {
                    if(x$distribution$name %in% c("gaussian", "laplace", "tdist")) 
                      return(NULL)
                    if(is.null(x$classes)) {
                      out <- if(any(names(x) == "obsLevels")) x$obsLevels else NULL
                    } else {
                      out <- x$classes
                    }
                    out
                  },
                  tags = c("Tree-Based Model", "Boosting", "Ensemble Model", "Implicit Feature Selection"),
                  sort = function(x) {
                    # This is a toss-up, but the # trees probably adds
                    # complexity faster than number of splits
                    x[order(x$n.trees, x$interaction.depth, x$shrinkage),] 
                  })
