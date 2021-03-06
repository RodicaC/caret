modelInfo <- list(label = "Boosted Generalized Linear Model",
                  library = "mboost",
                  type = c("Regression", "Classification"),
                  parameters = data.frame(parameter = c('mstop', 'prune'),
                                          class = c("numeric", "character"),
                                          label = c('# Boosting Iterations', 'AIC Prune?')),
                  grid = function(x, y, len = NULL) 
                    data.frame(mstop = floor((1:len) * 50), prune = "no"),
                  loop = function(grid) {   
                    grid <- grid[order(grid$mstop, decreasing = TRUE),, drop = FALSE]
                    loop <- grid[1,,drop = FALSE]
                    submodels <- list(grid[-1, "mstop", drop = FALSE])         
                    list(loop = loop, submodels = submodels)
                  },
                  fit = function(x, y, wts, param, lev, last, classProbs, ...) {                
                    ##check for control list and over-write mstop
                    theDots <- list(...)
                    if(any(names(theDots) == "control"))
                    {
                      theDots$control$mstop <- param$mstop 
                      ctl <- theDots$control
                      theDots$control <- NULL
                    } else ctl <- boost_control(mstop = param$mstop)
                    
                    if(!any(names(theDots) == "family"))
                      theDots$family <- if(is.factor(y)) Binomial() else GaussReg()              
                    
                    ## pass in any model weights
                    if(!is.null(wts)) theDots$weights <- wts                       
                    
                    dat <- if(is.data.frame(x)) x else as.data.frame(x)
                    dat$.outcome <- y
                    modelArgs <- c(list(formula = as.formula(".outcome ~ ."), data = dat, control = ctl), 
                                   theDots)
                    
                    out <- do.call(mboost:::glmboost.formula, modelArgs)
                    
                    if(param$prune == "yes")
                    {
                      out <- if(is.factor(y)) out[mstop(AIC(out, "classical"))] else out[mstop(AIC(out))]
                    }
                    
                    ## for easier printing (and tracebacks), we'll try to make the calls shorter
                    ## by adding dummy object names instead of the long obkect definitions that
                    ## currently exist
                    out$call["x"] <- "xData"         
                    out$call["y"] <- "yData"         
                    out
                    },
                  predict = function(modelFit, newdata, submodels = NULL) {
                    predType <- ifelse(modelFit$problemType == "Classification", "class", "response")
                    if(!is.data.frame(newdata)) newdata <- as.data.frame(newdata)
                    out <- predict(modelFit, newdata, type = predType)
                    
                    if(!is.null(submodels))
                    {
                      tmp <- vector(mode = "list", length = nrow(submodels) + 1)
                      tmp[[1]] <- as.vector(out)
                      
                      for(j in seq(along = submodels$mstop))
                        tmp[[j+1]]  <- as.vector(predict(modelFit[submodels$mstop[j]], 
                                                         newdata, 
                                                         type = predType))
                      
                      out <- tmp
                    } 
                    out         
                  },
                  prob = function(modelFit, newdata, submodels = NULL) {
                    if(!is.data.frame(newdata)) newdata <- as.data.frame(newdata)
                    lp <- predict(modelFit, newdata)
                    out <- cbind( binomial()$linkinv(-lp), 1 - binomial()$linkinv(-lp))
                    colnames(out) <- modelFit$obsLevels
                    if(!is.null(submodels))
                    {
                      tmp <- vector(mode = "list", length = nrow(submodels) + 1)
                      tmp[[1]] <- out
                      
                      for(j in seq(along = submodels$mstop))
                      {                           
                        tmpProb <- predict(modelFit[submodels$mstop[j]], newdata)
                        tmpProb <- cbind(binomial()$linkinv(-tmpProb),
                                         1 - binomial()$linkinv(-tmpProb))
                        colnames(tmpProb) <- modelFit$obsLevels
                        tmp[[j+1]] <- as.data.frame(tmpProb[, modelFit$obsLevels,drop = FALSE])           
                      }
                      out <- tmp
                    }                        
                    out
                  },
                  predictors = function(x, ...) {
                    strsplit(variable.names(x), ", ")[[1]]
                  },
                  levels = function(x) levels(x$response),
                  tags = c("Generalized Linear Model", "Ensemble Model", "Boosting", "Linear Classifier"),
                  sort = function(x) x[order(x$mstop, x$prune),])
