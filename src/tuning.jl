abstract type TuningStrategy <: MLJ.MLJType end

mutable struct Grid <: TuningStrategy
    resolution::Int
end

Grid(;resolution=10) = Grid(resolution)

# TODO: make fitresult type `TrainableModel` more concrete.

mutable struct TunedModel{T,M<:MLJ.Model} <: MLJ.Supervised{MLJ.TrainableModel}
    model::M
    tuning_strategy::T
    resampling_strategy
    measure
    param_ranges::Params
    report_measurements::Bool
end

function TunedModel(;model=ConstantRegressor(),
                    tuning_strategy=Grid(),
                    resampling_strategy=Holdout(),
                    measure=rms,
                    param_ranges=Params(),
                    report_measurements=true)
    !isempty(param_ranges) || @warn "Field param_ranges not specified."
    return TunedModel(model, tuning_strategy, resampling_strategy,
                      measure, param_ranges, report_measurements)
end

function MLJ.fit(tuned_model::TunedModel{Grid,M}, verbosity, X, y) where M

    resampler = Resampler(model=tuned_model.model,
                          strategy=tuned_model.resampling_strategy,
                          measure=tuned_model.measure)

    trainable_resampler = trainable(resampler, X, y)

    # tuple of `ParamRange` objects:
    ranges = MLJ.flat_values(tuned_model.param_ranges)

    # tuple of iterators over hyper-parameter values:
    iterators = map(ranges) do range
        if range isa MLJ.NominalRange
            MLJ.iterator(range)
        elseif range isa MLJ.NumericRange
            MLJ.iterator(range, tuned_model.tuning_strategy.resolution)
        else
            throw(TypeError(:iterator, "", MLJ.ParamRange, rrange))            
        end
    end

    # nested sequence of `:hyperparameter => iterator` pairs:
    param_iterators = copy(tuned_model.param_ranges, iterators)

    # iterator over models:
    model_iterator = MLJ.iterator(tuned_model.model, param_iterators)

    L = length(model_iterator)
    measurements = Vector{Float64}(undef, L)


    # initialize search for best model:
    m = 1 # model counter
    best_model = tuned_model.model
    best_measurement = Inf

    # evaluate all the models using specified resampling_strategy:

    verbosity < 1 || println("Searching for best model...")
    for model in model_iterator
        if verbosity > 0
            print("model number: $m")
        end
        
        trainable_resampler.model.model = model
        fit!(trainable_resampler, verbosity=verbosity-1)
        e = evaluate(trainable_resampler)
        verbosity < 1 || println("\t measurement: $e    ")
        measurements[m] = e
        if e < best_measurement
            best_model = model
            best_measurement = e
        end
        m += 1
    end
    verbosity < 1 || println()
    verbosity < 1 || println("Training best model on all supplied data...")

    # tune best model on all the data:
    fitresult = trainable(best_model, X, y)
    fit!(fitresult)

    if tuned_model.report_measurements
        report = Dict{Symbol, Any}()
        report[:models] = collect(model_iterator)
        report[:measurements] = measurements
        report[:best_measurement] = best_measurement
    else
        report = nothing
    end
    
    cache = nothing
    
    return fitresult, cache, report
    
end

MLJ.predict(tuned_model::TunedModel, fitresult, Xnew) = predict(tuned_model.model, fitresult, Xnew)
MLJ.best(model::TunedModel, fitresult) = fitresult.model
    
