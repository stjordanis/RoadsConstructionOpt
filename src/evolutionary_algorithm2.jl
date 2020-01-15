#1. Alternative selection
function tournament(groupSize :: Int,fitness::Array{Tuple{Float64,Array{Tuple{Int64,Int64},1}},1} = population, N::Int64 = length(population))
        selection = fill(0,N)
        nFitness = length(fitness)
        for i in 1:N
            contender = unique(rand(1:nFitness, groupSize))
            while length(contender) < groupSize
                contender = unique(vcat(contender, rand(1:nFitness, groupSize - length(contender))))
            end
            winner = first(contender)
            winnerFitness = fitness[winner]
            for idx = 2:groupSize
                c = contender[idx]
                if winnerFitness > fitness[c]
                    winner = c
                    winnerFitness = fitness[c]
                end
            end
            selection[i] = winner
        end
        return selection
    return tournament
end

#2. Alternative crossover
function vswap!(v1::Vector{Tuple{Int,Int}}, v2::Vector{Tuple{Int,Int}}, idx::Int)
    val = v1[idx]
    v1[idx] = v2[idx]
    v2[idx] = val
end

function twopoint(v1::Vector{Tuple{Int,Int}}, v2::Vector{Tuple{Int,Int}})
    l = length(v1)
    c1 = copy(v1)
    c2 = copy(v2)
    from, to = rand(1:l, 2)
    from, to = from > to ? (to, from) : (from, to)
    for i in from:to
        vswap!(c1, c2, i)
    end
    return c1, c2
end

#3. Alternative mutation
function insertion!(
    population::Vector{Tuple{Float64,Vector{Tuple{Int,Int}}}},
    id::Int,
)
    seq = population[id][2]
    swap1, swap2 = rand(1:length(seq), 2)
    val = seq[swap1]
    val2 = seq[swap2]
    deleteat!(seq, swap1)
    insert!(seq, swap2, val2)
    population[id] = (NaN, seq)
end


"""
    optimize2!(
        sim_data::OpenStreetMapXDES.SimData,
        λ_ind::Float64,
        routes::Vector{Tuple{Int,Int}},
        no_solutions::Int,
        roadwork_time::Int,
        no_of_partitions::Int,
        crossover_rate::Float64,
        mutation_rate::Float64,
        elitism::Float64;
        burning_time::Int = 50,
        runtime::Int = 20,
        ϵ = 0.0001,
        maxiter::Int = 500,
        toliter::Int = 10,
        )

TODO Marcin - Describe what function does
in particular add reference to the paper that has been used to implement it
#optimize2! - function created to find the best solution of roadworks by finding the proper sequence of closures using genetic algorithm
#References:
#Mainly article nr 2. but also to some extent: articles 4. and 7. (see: https://github.com/OpalskiM/RoadsConstructionOpt/blob/master/docs/Literature.jl)

**Arguments**

* `sim_data` : initally generated artificial population
* `λ_ind` : learning rate
* `routes` : array of edges to remove from the graph
* `no_solutions` : number of solutions
* `roadwork_time` : approximate length of roadwork of single segment
* `no_of_partitions` : number of steps in roadwork process
* `crossover_rate` : crossover rate of the GA crossover operator 
* `mutation_rate` : mutation rate of the GA mutation operator
* `elitism` : elitism rate of the GA
* `burning_time` : number of traffic simulations
* `runtime` : number of simulations in reference scenario (to compare with optimized solution)
* `ϵ` : tolerance of single iteration
* `maxiter` : maximal number of iterations of GA
* `toliter` : maximal number of iterations of GAnot improving the performance (stop criteria)
"""
function optimize2!(
    sim_data::OpenStreetMapXDES.SimData,
    λ_ind::Float64,
    routes::Vector{Tuple{Int,Int}},
    no_solutions::Int,
    roadwork_time::Int,
    no_of_partitions::Int,
    crossover_rate::Float64,
    mutation_rate::Float64,
    elitism::Float64;
    burning_time::Int = 50,
    runtime::Int = 20,
    ϵ = 0.0001,
    maxiter::Int = 500,
    toliter::Int = 10,
)
    #let no_solution be even:
    mod(no_solutions, 2) == 1 && (no_solutions += 1)
    #prepare enviroment:
    run_sim!(sim_data, λ_ind, burning_time)
    #get reference scenario:
    reference_times = run_sim!(deepcopy(sim_data), λ_ind, runtime)
    #generate first solutions:
    population = Tuple{Float64,Vector{Tuple{Int,Int}}}[]
    for i in 1:no_solutions
        push!(
            population,
            get_solution(
                deepcopy(sim_data),
                shuffle(routes),
                reference_times,
                λ_ind,
                roadwork_time,
                no_of_partitions,
            ),
        )
    end
    @info "First generation done! [thread $(Threads.threadid())]"
    sort!(population)
    (best_fit, best_solution), _ = findmin(population)
    #println("best_fit=",best_fit)
    (worst_fit, worst_solution), _ = findmax(population)
    #main loop:
    iter = 1
    fit_iter = 1
    δ = Inf
    while true
        offspring = similar(population)
        #mating
        mates = tournament(1) ##################### 1. Change (tournament)
        offidx = randperm(no_solutions)
        for i in 1:2:no_solutions
            j = i + 1
            if rand() < crossover_rate
                seq1, seq2 = twopoint(
                    population[mates[offidx[i]]][2],
                    population[mates[offidx[j]]][2],
                ) ################## 2. Change (twopoint)
                offspring[i], offspring[j] = (NaN, seq1), (NaN, seq2)
            else
                offspring[i], offspring[j] = population[mates[i]], population[mates[j]]
            end
        end
        #mutation
        for i in 1:no_solutions
            (rand() < mutation_rate) && insertion!(offspring, i) ################ 3. Change (insertion)
        end
        #elitism
        for i in 1:Int(round(elitism * no_solutions))
            idx = rand(1:no_solutions)
            offspring[idx] = population[i]
        end
        #compute new fitnesses
        for (id, individual) in enumerate(offspring)
            if isnan(individual[1])
                offspring[id] = get_solution(
                    deepcopy(sim_data),
                    individual[2],
                    reference_times,
                    λ_ind,
                    roadwork_time,
                    no_of_partitions,
                )
            end
        end
        #convergence
        population = offspring
        sort!(population)

        (next_best_fit, next_best_solution), _ = findmin(population)
        #println("next_best_fit=",next_best_fit)
        (next_worst_fit, next_worst_solution), _ = findmax(population)
        (next_worst_fit > worst_fit) && (worst_fit = next_worst_fit; worst_solution = next_worst_solution)
        δ = abs(next_best_fit - best_fit)
        println("δ=$δ")
        best_fit= next_best_fit
        best_solution = deepcopy(next_best_solution)
        if δ < ϵ
            fit_iter > toliter && break
            fit_iter += 1
        else
            fit_iter = 1
        end
        iter += 1
        iter >= maxiter && break
        @info "iteration $iter done  [thread $(Threads.threadid())]"
    end
    return (best_fit=best_fit, best_solution=best_solution, worst_fit=worst_fit, worst_solution=worst_solution, iter=iter, fit_iter=fit_iter)
end
