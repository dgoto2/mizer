#' Set predation kernel
#' 
#' The predation kernel determines the distribution of prey sizes that a
#' predator feeds on. It is used in [getEncounter()] when calculating
#' the rate at which food is encountered and in [getPredRate()] when
#' calculating the rate at which a prey is predated upon. The predation kernel
#' can be a function of the predator/prey size ratio or it can be a function of
#' the predator size and the prey size separately. Both types can be set up with
#' this function.
#' 
#' @section Setting predation kernel:
#' \strong{Kernel dependent on predator to prey size ratio}
#' 
#' If the `pred_kernel` argument is not supplied, then this function sets a
#' predation kernel that depends only on the ratio of predator mass to prey
#' mass, not on the two masses independently. The shape of that kernel is then
#' determined by the `pred_kernel_type` column in species_params.
#'
#' The default for `pred_kernel_type` is "lognormal". This will call the function
#' [lognormal_pred_kernel()] to calculate the predation kernel.
#' An alternative pred_kernel type is "box", implemented by the function
#' [box_pred_kernel()], and "power_law", implemented by the function
#' [power_law_pred_kernel()]. These functions require certain species
#' parameters in the species_params data frame. For the lognormal kernel these
#' are `beta` and `sigma`, for the box kernel they are `ppmr_min`
#' and `ppmr_max`. They are explained in the help pages for the kernel
#' functions. Except for `beta` and `sigma`, no defaults are set for
#' these parameters. If they are missing from the species_params data frame then
#' mizer will issue an error message.
#'
#' You can use any other string for `pred_kernel_type`. If for example you
#' choose "my" then you need to define a function `my_pred_kernel` that you can
#' model on the existing functions like [lognormal_pred_kernel()].
#' 
#' When using a kernel that depends on the predator/prey size ratio only, mizer
#' does not need to store the entire three dimensional array in the MizerParams
#' object. Such an array can be very big when there is a large number of size
#' bins. Instead, mizer only needs to store two two-dimensional arrays that hold
#' Fourier transforms of the feeding kernel function that allow the encounter
#' rate and the predation rate to be calculated very efficiently. However, if
#' you need the full three-dimensional array you can calculate it with the
#' [getPredKernel()] function.
#' 
#' \strong{Kernel dependent on both predator and prey size}
#' 
#' If you want to work with a feeding kernel that depends on predator mass and
#' prey mass independently, you can specify the full feeding kernel as a
#' three-dimensional array (predator species x predator size x prey size).
#'
#' You should use this option only if a kernel dependent only on the
#' predator/prey mass ratio is not appropriate. Using a kernel dependent on
#' predator/prey mass ratio only allows mizer to use fast Fourier transform
#' methods to significantly reduce the running time of simulations.
#'
#' The order of the predator species in `pred_kernel` should be the same
#' as the order in the species params dataframe in the `params` object. If you
#' supply a named array then the function will check the order and warn if it is
#' different.
#' 
#' @param params A MizerParams object
#' @param pred_kernel Optional. An array (species x predator size x prey size)
#'   that holds the predation coefficient of each predator at size on each prey
#'   size. If not supplied, a default is set as described in section "Setting
#'   predation kernel".
#' @param reset `r lifecycle::badge("experimental")`
#'   If set to TRUE, then the predation kernel will be reset to the
#'   value calculated from the species parameters, even if it was previously
#'   overwritten with a custom value. If set to FALSE (default) then a
#'   recalculation from the species parameters will take place only if no custom
#'   value has been set.
#' @param ... Unused
#' 
#' @return `setPredKernel()`: A MizerParams object with updated predation kernel.
#' @export
#' @family functions for setting parameters
#' @examples
#' \dontrun{
#' ## Set up a MizerParams object
#' params <-  NS_params
#' 
#' ## If you change predation kernel parameters after setting up a model, 
#' #  this will be used to recalculate the kernel
#' species_params(params)["Cod", "beta"] <- 200
#' 
#' ## You can change to a different predation kernel type
#' species_params(params)$ppmr_max <- 4000
#' species_params(params)$ppmr_min <- 200
#' species_params(params)$pred_kernel_type <- "box"
#' plot(w_full(params), getPredKernel(params)["Cod", 100, ], type="l", log="x")
#' 
#' ## If you need a kernel that depends also on prey size you need to define
#' # it yourself.
#' pred_kernel <- getPredKernel(params)
#' pred_kernel["Herring", , ] <- sweep(pred_kernel["Herring", , ], 2, 
#'                                     params@w_full, "*")
#' params<- setPredKernel(params, pred_kernel = pred_kernel)
#' }
setPredKernel <- function(params,
                          pred_kernel = NULL,
                          reset = FALSE, ...) {
    assert_that(is(params, "MizerParams"),
                is.flag(reset))
    
    if (reset) {
        if (!is.null(pred_kernel)) {
            warning("Because you set `reset = TRUE`, the value you provided ", 
                    "for `pred_kernel` will be ignored and a value will be ",
                    "calculated from the species parameters.")
            pred_kernel <- NULL
        }
        comment(params@pred_kernel) <- NULL
    }
    
    if (!is.null(pred_kernel)) {
        if (is.null(comment(pred_kernel))) {
            if (is.null(comment(params@pred_kernel))) {
                comment(pred_kernel) <- "set manually"
            } else {
                comment(pred_kernel) <- comment(params@pred_kernel)
            }
        }
        # A pred kernel was supplied, so check it and store it
        assert_that(is.array(pred_kernel))
        # psi is used in the next line just because it has the right dimension
        assert_that(identical(dim(pred_kernel), 
                              c(dim(params@psi), length(params@w_full))))
        if (!is.null(dimnames(pred_kernel)) && 
            !all(dimnames(pred_kernel)[[1]] == params@species_params$species)) {
            stop(paste0("You need to use the same ordering of species as in the ",
                        "params object: ", toString(params@species_params$species)))
        }
        assert_that(all(pred_kernel >= 0))
        dimnames(pred_kernel) <- 
            list(sp = params@species_params$species,
                 w_pred = signif(params@w, 3),
                 w_prey = signif(params@w_full, 3))
        params@pred_kernel <- pred_kernel
        params@time_modified <- lubridate::now()
        return(params)
    }
    
    ## Set a pred kernel dependent on predator/prey size ratio only
    
    # If pred_kernel_type is not supplied use "lognormal"
    params <- default_pred_kernel_params(params)
    
    species_params <- params@species_params
    pred_kernel_type <- species_params$pred_kernel_type
    no_sp <- nrow(species_params)
    no_w <- length(params@w)
    no_w_full <- length(params@w_full)
    ft_pred_kernel_e <-
        array(NA, dim = c(no_sp, no_w_full),
              dimnames = list(sp = species_params$species, k = 1:no_w_full))
    ft_pred_kernel_p <- ft_pred_kernel_e
    # Vector of predator/prey mass ratios
    # The smallest predator/prey mass ratio is 1
    ppmr <- params@w_full / params@w_full[1]
    phis <- get_phi(species_params, ppmr)
    # Do not allow feeding at own size
    phis[, 1] <- 0
    fte <- 
    for (i in 1:no_sp) {
        phi <- phis[i, ]
        # Fourier transform of feeding kernel for evaluating available energy
        ft_pred_kernel_e[i, ] <- fft(phi)
        # Fourier transform of feeding kernel for evaluating predation rate
        ri <- min(max(which(phi > 0)), no_w_full - 1)  # index of largest ppmr
        phi_p <- rep(0, no_w_full)
        phi_p[(no_w_full - ri + 1):no_w_full] <- phi[(ri + 1):2]
        ft_pred_kernel_p[i, ] <- fft(phi_p)
    }
    
    # Prevent resetting if full slot has been commented
    if (!is.null(comment(params@pred_kernel))) {
        # Issue warning but only if a change was actually requested
        if (different(ft_pred_kernel_e, params@ft_pred_kernel_e) ||
            different(ft_pred_kernel_p, params@ft_pred_kernel_p)) {
            message("You have set a custom predation kernel and so it ",
                    "will not be recalculated from the species parameters ",
                    "unless you set `reset = TRUE`.")
        }
        return(params)
    }
    params@ft_pred_kernel_e[] <- ft_pred_kernel_e
    params@ft_pred_kernel_p[] <- ft_pred_kernel_p
    
    params@time_modified <- lubridate::now()
    return(params)
}

#' @rdname setPredKernel
#' @return `getPredKernel()` or equivalently `pred_kernel()`: An array (predator
#'   species x predator_size x prey_size)
#' @export
getPredKernel <- function(params) {
    # This function is more complicated than you might have thought because
    # usually the predation kernel is not stored in the MizerParams object,
    # but rather only the Fourier coefficients needed for fast calculation of
    # the convolution integrals. 
    assert_that(is(params, "MizerParams"))
    if (length(dim(params@pred_kernel)) > 1) {
        return(params@pred_kernel)
    }
    species_params <- default_pred_kernel_params(params@species_params)
    pred_kernel_type <- species_params$pred_kernel_type
    no_sp <- nrow(species_params)
    no_w <- length(params@w)
    no_w_full <- length(params@w_full)
    # Vector of predator/prey mass ratios
    # The smallest predator/prey mass ratio is 1
    ppmr <- params@w_full / params@w_full[1]
    phis <- get_phi(species_params, ppmr)
    # Do not allow feeding at own size
    phis[, 1] <- 0
    pred_kernel <- 
        array(0,
              dim = c(no_sp, no_w, no_w_full),
              dimnames = list(sp = species_params$species,
                              w_pred = signif(params@w, 3),
                              w_prey = signif(params@w_full, 3)))
    for (i in 1:no_sp) {
        min_w_idx <- no_w_full - no_w + 1
        for (k in seq_len(no_w)) {
            pred_kernel[i, k, (min_w_idx - 1 + k):1] <-
                phis[i, 1:(min_w_idx - 1 + k)]
        }
    }
    return(pred_kernel)
}

#' @rdname setPredKernel
#' @export
pred_kernel <- function(params) {
    getPredKernel(params)
}

#' @rdname setPredKernel
#' @param value pred_kernel
#' @export
`pred_kernel<-` <- function(params, value) {
    setPredKernel(params, pred_kernel = value)
}

#' Set defaults for predation kernel parameters
#'
#' If the predation kernel type has not been specified for a species, then it
#' is set to "lognormal" and the default values are set for the parameters
#' `beta` and `sigma`.
#' @param object Either a MizerParams object or a species parameter data frame
#' @return The `object` with updated columns in the species params data frame.
#' @export
#' @concept helper
default_pred_kernel_params <- function(object) {
    if (is(object, "MizerParams")) {
        # Nothing to do if full pred kernel has been specified
        if (length(dim(object@pred_kernel)) > 1) {
            return(object)
        }
        species_params <- object@species_params
    } else {
        species_params <- object
    }
    
    species_params <- set_species_param_default(species_params,
                                                "pred_kernel_type",
                                                "lognormal")
    # For species where the pred_kernel_type is lognormal, set defaults for
    # sigma and beta if none are supplied
    if (any(species_params$pred_kernel_type == "lognormal")) {
        species_params <- set_species_param_default(species_params,
                                                    "beta", 30)
        species_params <- set_species_param_default(species_params,
                                                    "sigma", 2)
    }
    if  (is(object, "MizerParams")) {
        object@species_params <- species_params
        return(object)
    } else {
        return(species_params)
    }
}

#' Get values from feeding kernel function
#' 
#' This involves finding the feeding kernel function for each species, using the
#' pred_kernel_type parameter in the species_params data frame, checking that it
#' is valid and all its arguments are contained in the species_params data
#' frame, and then calling this function with the ppmr vector.
#' 
#' @param species_params A species parameter data frame
#' @param ppmr Values of the predator/prey mass ratio at which to evaluate the
#'   predation kernel function
#' @return An array (species x ppmr) with the values of the predation kernel
#'   function
#' @export
#' @concept helper
get_phi <- function(species_params, ppmr) {
    assert_that(is.data.frame(species_params))
    no_sp <- nrow(species_params)
    species_params <- default_pred_kernel_params(species_params)
    phis <- array(dim = c(no_sp, length(ppmr)))
    for (i in 1:no_sp) {
        pred_kernel_func_name <- paste0(species_params$pred_kernel_type[i],
                                        "_pred_kernel")
        pred_kernel_func <- get0(pred_kernel_func_name)
        assert_that(is.function(pred_kernel_func))
        args <- names(formals(pred_kernel_func))
        if (!("ppmr" %in% args)) {
            stop("The predation kernel function ",
                 pred_kernel_func_name,
                 "needs the argument 'ppmr'.")
        }
        # lop off the compulsory arg
        args <- args[!(args %in% "ppmr")]
        missing <- !(args %in% colnames(species_params))
        if (any(missing)) {
            stop("The following arguments for the predation kernel function ",
                 pred_kernel_func_name,
                 " are missing from the parameter dataframe: ",
                 toString(args[missing]))
        }
        pars <- c(ppmr = list(ppmr), as.list(species_params[i, args]))
        phi <- do.call(pred_kernel_func_name, args = pars)
        if (any(is.na(phi)) && 
            (species_params$interaction_resource[i] > 0 ||
             any(interaction[i, ] > 0))) {
            stop("The function ", pred_kernel_func_name,
                 " returned NA. Did you correctly specify all required",
                 " parameters in the species parameter dataframe?")
        }
        phis[i, ] <- phi
    }
    return(phis)
}
