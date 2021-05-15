# Import libraries
#import os
#import glob
#import numpy as np
using Random
using Distributions # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("Distributions")'
using StatsBase     # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("StatsBase")'
#using Statistics
#from itertools import accumulate
#import matplotlib.pyplot as plt
using DataFrames    #If necessary, donwload the package at the pkg prompt, i.e. add DataFrames #import pandas as pd
using Printf        # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("Printf")'
using CSV           # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("CSV")'
#from collections import defaultdict
# %matplotlib inline

#import logging

# For each simulation, choose a different starting vaccination rate
INITIAL_VACCINATION_RATE = 0.10
#INITIAL_VACCINATION_RATE = 0.25
#INITIAL_VACCINATION_RATE = 0.50
#INITIAL_VACCINATION_RATE = 0.75
#INITIAL_VACCINATION_RATE = 0.90

# Global properties - used for all trials
# Variables from version 1
maxIterationDays    = 100
numTrials           = 1000 #1000

# New variables for version 2
# 20210424:Cesar - moved dictionaries to global level from inside create_db function
gender_dict = Dict(1 => "M", 0 => "F")
health_dict = Dict(
      0 => "Never infected"
    , 1 => "Sick"
    , 2 => "Recovered"
    , 3 => "Deceased"
)
def_rows            = Int16(900) #900
def_dayssic_default = Int8(5)
def_gender_prob     = 0.52
def_avg_age         = 46.0
def_std_age         = 13.0
def_pois_comorbid   = 0.7 #1.0 - this may be too high (we end up with a max of 9 comorbidities)
def_asym_prob       = 0.02
def_anti_prob       = 0.09
def_initsick_prob   = 0.05

#############################################################################################
# R-naught value (each sick person can infect R0 healthy people per interaction i.e. per day
# - not the traditional R0 which is not per interaction, but rather per infection)
# This number has been carefully tuned and probably shouldn't be modified or if so, by little
R0 = 0.18 #0.25
#############################################################################################
max_days_sick = 14
death_threshold = 0.3 # The number that serves as the minimum for a random number (to max = 1.0)
                      # above which people die if their probability of death > the random number

saving_throw_vaccination = 1.0 # Use 1.0 to make vaccination, even if not effective, save the sick
                               # from dying or a number less than 1.0 to decrease chances of dying

# Julia has some funny requirements about using optional arguments, detailed here:
# https://docs.julialang.org/en/v1/manual/functions/#Optional-Arguments
# When using optional arguments, apparently, we need at least 2 non-optional (and unnamed, i.e. positional arguments)
function create_db_population(
      rows            :: Int16;
      dayssic_default :: Int8    = Int8(5)
    , gender_prob     :: Float64 = 0.52
    , avg_age         :: Float64 = 46.0
    , std_age         :: Float64 = 13.0
    , pois_comorbid   :: Float64 = 1.0
    , asym_prob       :: Float64 = 0.02
    , anti_prob       :: Float64 = 0.09
    , initsick_prob   :: Float64 = 0.05
)
    """[summary]

    Args:
        rows (int, optional): [Size of the population]. Defaults to 900.
        gender_prob (float, optional): [Gender split percent]. Defaults to 0.52.
        avg_age (int, optional): [Average age of population]. Defaults to 46.
        std_age (int, optional): [Standard deviation of population]. Defaults to 13.
        pois_comorbid (float, optional): [Poisson distribution for # of comorbidities], Defaults to 1.0
        asym_prob (float, optional): [Probability of asymptomatic]. Defaults to .02.
        anti_prob (float, optional): [Probability of Crazy]. Defaults to .09.
        initsick_prob (float, optional): [% of population initially sick]. Defaults to 0.05
        dayssic_default (int, optional): [# of days sick for who are initially sick]. Defaults to 5

    Returns:
        [DataFrame]: [DataFrame of attributes for the population]
    """

    #------------------------------------------------------------------------
    # 20210424:Cesar - Added assert section to keep parameters to sane levels
    @assert rows > 1 and rows < 100000 \
        "Parameter 'rows' (population size) must be between 2 and 99999"
        
    @assert gender_prob >= 0 and gender_prob <= 1.0 \
        "Parameter 'gender_prob' (Percent Males) must be between 0.0 and 1.0"
        
    @assert avg_age >= 20 and avg_age <= 60 \
        "Parameter 'avg_age' (Average Age) must be between 20 and 60"
        
    @assert std_age >= 10 and std_age <= 20 \
        "Parameter 'std_age' (Standard Deviation Age) must be between 10 and 20"
        
    @assert pois_comorbid >= 0.5 and pois_comorbid <= 4.0 \
        "Parameter 'pois_comorbid' (Comorbidities count) must be between 0.5 and 4.0"
        
    @assert asym_prob >= 0.0 and asym_prob <= 1.0 \
        "Parameter 'asym_prob' (Percent Asymmetric) must be between 0.0 and 1.0"
        
    @assert anti_prob >= 0.0 and anti_prob <= 1.0 \
        "Parameter 'anti_prob' (Percent AntiVax) must be between 0.0 and 1.0"
        
    @assert initsick_prob >= 0.0 and initsick_prob <= 1.0 \
        "Parameter 'initsick_prob' (Percent Initially Sick) must be between 0.0 and 1.0"
        
    @assert dayssic_default >= 1 and dayssic_default <= 14 \
        "Parameter 'dayssic_default' (Initially days sick) must be between 1 and 14"
    #------------------------------------------------------------------------

    features = [
          "id"
        , "Gender"
        , "Age"
        , "Comorbidity"
        , "Asymptomatic"
        , "Antivax"
        , "Vaccinated"
        , "Veffective"
        , "DaysSick"
        , "HealthStatus"
    ]
#    df = DataFrame(
#          id           = Int16[]
#        , Gender       = Int16[]
#        , Age          = Int16[]
#        , Comorbidity  = Int16[]
#        , Asymptomatic = Int16[]
#        , Antivax      = Int16[]
#        , Vaccinated   = Int16[]
#        , Veffective   = Int16[]
#        , DaysSick     = Int16[]
#        , HealthStatus = Int16[]  
#    )

    df = DataFrame()

    df.id = collect(range(1, length=rows))

    df.Gender = convert(Vector{Int16}, rand(Distributions.Bernoulli(gender_prob), rows))

    df.Age = round.(rand(Distributions.Normal(avg_age, std_age), rows))

    df.Comorbidity = round.(rand(Distributions.Poisson(pois_comorbid), rows))

    df.Asymptomatic = rand(Distributions.Bernoulli(asym_prob), rows)

    # Use the column Veffective for both counting how many people get vaccinated
    # and of those, how many the vaccine was effective
    # First, get the indexes of AntiVaxers because they will not take the vaccine anyway
    df.Antivax = rand(Distributions.Bernoulli(anti_prob), rows)
    ids_ProVax = df[df.Antivax .== 0, "id"]
    # Now get the count of those who will get the vaccine (minimum of
    # the vaccination rate * population, and those who are not antivax)
    count_get_vaccine = minimum([floor(INITIAL_VACCINATION_RATE * rows), length(ids_ProVax)])
    ids_vaccinated = sample(ids_ProVax, Int16(count_get_vaccine), replace=false) # #StatsBase.direct_sample!
    # Set that number of people to be vaccinated
    df.Vaccinated = vec(falses(rows, 1))
    df[ids_vaccinated, "Vaccinated"] .= 1
    # Of those receiving the vaccine only 70% will be effective
    # randomly choose 70% of the ids representing vaccinated people
    ids_effective_vaccine = sort(sample(
        ids_vaccinated, Int16(round(0.7 * length(ids_vaccinated))), replace=false
    ))
    # and set those selected to having an effective vaccine
    df.Veffective = vec(falses(rows, 1))
    df[ids_effective_vaccine, "Veffective"] .= 1
    # Next, of those who are not vaccinated, choose a random set of ids
    # representing the starting infectious population
    # This will be the minimum of that percentage of the population
    # and the number who do not have an effective vaccine
    ids_ineffective_vaccine = df[df.Veffective .== 0, "id"]
    count_starting_sick = Int16(minimum([round(initsick_prob * rows), length(ids_ineffective_vaccine)]))
    
    ids_starting_sick = sample(
        ids_ineffective_vaccine, count_starting_sick, replace=false
    )
    df.DaysSick = vec(zeros(Int16, (rows, 1)))
    df[ids_starting_sick, "DaysSick"] .= def_dayssic_default
    df.HealthStatus = vec(zeros(Int16, (rows, 1)))
    df[ids_starting_sick, "HealthStatus"] .= 1

    #println(df)

    return df
end

function create_db_results()
    features = [
          "TrialID"
        , "Day"
        , "CountNeverInfected"
        , "CountSick"
        , "CountRecovered"
        , "CountDeceased"
        , "CountVaccinated"
        , "CountEffectiveVaccine"
        , "CountCumSick"
        , "CountCumDead"
        , "CountCumRecovered"
    ]

    df = DataFrame(
          TrialID               = Int32[]
        , Day                   = Int32[]
        , CountNeverInfected    = Int32[]
        , CountSick             = Int32[]
        , CountRecovered        = Int32[]
        , CountDeceased         = Int32[]
        , CountVaccinated       = Int32[]
        , CountEffectiveVaccine = Int32[]
        , CountCumSick          = Int32[]
        , CountCumDead          = Int32[]
        , CountCumRecovered     = Int32[]
    )

    return df

end

# Ensure our output directory exists
mkpath("output")

# Create a text file for recording diagnostic data
file_diagnostics = open("output/diagnostics.txt", "w")

# Create a new results database
df_trials = create_db_results()

for n in collect(range(1, length=numTrials))
    #@printf(file_diagnostics, "%s\nTrial %i\n", ("#"^30), n)
    # For each trial, we create a new population database

    # Create a new randomized population for this trial
    df_sim = create_db_population(
          def_rows
        , dayssic_default = def_dayssic_default
        , gender_prob     = def_gender_prob
        , avg_age         = def_avg_age
        , std_age         = def_std_age
        , pois_comorbid   = def_pois_comorbid
        , asym_prob       = def_asym_prob
        , anti_prob       = def_anti_prob
        , initsick_prob   = def_initsick_prob
    )

    CountVaccinated = length(df_sim[df_sim.Vaccinated .== 1, "id"])
    CountEffectiveVaccine = length(df_sim[df_sim.Veffective .== 1, "id"])

    #@printf(file_diagnostics, "%s\nTrial %i\n%s\nStarting infection status\n%s\n", ("#"^30), n, ("="^30), df_sim)

    # Loop over the maximum number of days we are testing
    for i in collect(range(1, length=maxIterationDays))
        # For each day in the trial, we need to:
        # 1. Determine which population members are infectious
        #   a. Must be in status "sick"
        #   b. must not have quarantined (quarantine is affected by asymptomatic status)
        # 2. Determine which population members can become sick
        #   a. Must be currently in a "Never been sick" status
        #   b. Must be unvaccinated (AntiVax) or vaccinated, but with a failed vaccination
        # 3. Apply the R0 (R-naught) value selected for the infection
        #    to see how many of the healthy are infected by the sick

        #@printf(file_diagnostics, "%s\nDay %i\n", ("-"^30), i)

        # Get the ids of people who are sick (HealthStatus==1)
        # AND either are not self-isolating, or are asymptomatic
        ids_sick = df_sim[
            (df_sim.HealthStatus .== 1) .& ((df_sim.DaysSick .< 8) .| (df_sim.Asymptomatic .== 1))
        , "id"]
        #@printf(file_diagnostics, "IDs of infectious people: %s\n", ids_sick)

        # Get the ids of people who are healthy (HealthStatus==0)
        # AND either have effective vaccination, or are AntiVax
        ids_healthy = df_sim[
            (df_sim.HealthStatus .== 0) .& ((df_sim.Veffective .== 0) .| df_sim.Antivax .== 1)
        , "id"]
        #@printf(file_diagnostics, "IDs of healthy (susceptible) people: %s\n", ids_healthy)

        # Multiply the number of currently infectious people by R0 to determine
        # how many of the currently healthy people will get infected
        # We choose the minimum of the number of healthy people remaining
        # vs the number of sick (who have not self-isolated) * R0
        # This is because with replace=false, we cannot choose
        # more than the number of healthy people remaining
        ids_newly_infected = sample(
            ids_healthy, Int16(minimum([length(ids_healthy), round(length(ids_sick) * R0)])), replace=false
        )
        #file_diagnostics.write(f"IDs of newly infected people: {list(np.sort(ids_newly_infected))}\n")
        #@printf(file_diagnostics, "IDs of newly infected people: %s\n", sort(ids_newly_infected))

        # Update the population database
        # 1. Add the newly-infected
        df_sim[ids_newly_infected, "HealthStatus"] .= 1

        # 2. Increment the sick days (up to the maximum)
        # for everyone currently infected, including the newly-infected
        ids_updated_sick = df_sim[df_sim.HealthStatus .== 1, "id"]
        # This has surely got to be the weirdest ways I've had to translate Python functionality into Julia, but...
        # In the absence of (or at least unknown to me) a functionality likelihood
        # numpy.min which is broadcast over a numpy array, we need to do the folowing:
        # 1) Increment the number of sick days of all people who are sick by 1, regardless of whether we go over the maximum
        updatedDaysSick = df_sim[ids_updated_sick, "DaysSick"] .+ 1
        # 2) Create a boolean array of those DaysSick values that are at or below the maximum (resulting in ones and zeros)
        # then multiply this by the current value (resulting in the original value where the value is at or below the maximum
        # and 0 otherwise). Add these values to another array created by multiplying the boolean array (of values where
        # SickDays is above the maximum) by the maximum SickDays value, resulting in an array of zeros (where the maximum
        # has not been exceeded) and the maximum SickDays value where it has.
        df_sim[ids_updated_sick, "DaysSick"] = 
            ((updatedDaysSick .<= max_days_sick) .* updatedDaysSick)
            .+
            ((updatedDaysSick .> max_days_sick) .* max_days_sick)

        # 3. Determine recovery or death status if maximum days have been reached
        ids_sick_ended = df_sim[df_sim.DaysSick .>= max_days_sick, "id"]

        #@printf(file_diagnostics, "IDs of people for sickness ended: %s\n", sort(ids_sick_ended))
        df_sim[ids_sick_ended, "DaysSick"] .= 0

        # 4. Determine who might have died from the virus
        # - use age, comorbidity as factors that contribute to likelihood of death
        prob_death_by_age = exp.(df_sim[ids_sick_ended, "Age"] ./ 200.0) .- 1
        #@printf(file_diagnostics, "Age of people whose sickness ended: %s\n", df_sim[ids_sick_ended, "Age"])
        #@printf(file_diagnostics, "Probability of death (due to age) for sickness ended: %s\n", round.(prob_death_by_age, digits=2))

        prob_comorbid_mult = exp.(df_sim[ids_sick_ended, "Comorbidity"] ./ 20.0)
        #@printf(file_diagnostics, "Comorbidity multiplier for sickness ended: %s\n", round.(prob_comorbid_mult, digits=2))

        # The following will assign a multiplier of 1
        # (no change to the above multipliers) for people who had not taken the vaccine
        # or some number less than 1 (reducing the chances of death)
        # for those who took the vaccine, but where it was not effective
        prob_death_vaccine_mult = (
            1.0 .- ((df_sim[ids_sick_ended, "Vaccinated"]) .* saving_throw_vaccination)
        )

        # Calculate the final probability of death based on age and comorbidities as factors
        # that contribute to likelihood of death and on the probability of the vaccine to prevent
        # deaths even if ineffective for preventing getting sick in the first place
        prob_death = round.((prob_death_by_age .* prob_comorbid_mult .* prob_death_vaccine_mult), digits=2)
        #@printf(file_diagnostics, "Final probability of death for people whose sickness ended: %s\n", prob_death)

        # Randomly choose a threshold for each person
        # to see if they recover or die based on their final probability
        rand_death_threshold = rand(Distributions.Uniform(death_threshold, 1.0), length(prob_death))

        #@printf(file_diagnostics, "Death threshold for people whose sickness ended: %s\n", round.(rand_death_threshold, digits=2))
        actually_dead = (prob_death .>= rand_death_threshold)
        actually_live = (prob_death .< rand_death_threshold)

        #@printf(file_diagnostics, "Actually died when sickness ended: %s\n", actually_dead)
        idx_actually_dead = ids_sick_ended[actually_dead]

        #@printf(file_diagnostics, "IDs of people who actually died when sickness ended: %s\n", idx_actually_dead)
        idx_recovered = ids_sick_ended[actually_live]

        #@printf(file_diagnostics, "IDs of people who recovered when sickness ended: %s\n", idx_recovered)
        if length(idx_actually_dead) > 0
            df_sim[idx_actually_dead, "HealthStatus"] .= 3 # Deceased
        end
  
        if length(idx_actually_dead) > 0
            df_sim[idx_recovered, "HealthStatus"] .= 2 # Recovered
        end

        # At the end of the day, append a new row to the results DataFrame

        dict_vals = countmap(df_sim.HealthStatus)

        CountNeverInfected = 0 in keys(dict_vals) ? dict_vals[0] : 0  # Healthy
        CountSick          = 1 in keys(dict_vals) ? dict_vals[1] : 0  # Sick
        CountRecovered     = 2 in keys(dict_vals) ? dict_vals[2] : 0  # Recovered
        CountDeceased      = 3 in keys(dict_vals) ? dict_vals[3] : 0  # Dead

        lst_row = [
              n
            , i
            , CountNeverInfected #len(df_sim[df_sim['HealthStatus'] == 0])  # Healthy
            , CountSick          #len(df_sim[df_sim['HealthStatus'] == 1])  # Sick
            , CountRecovered     #len(df_sim[df_sim['HealthStatus'] == 2])  # Recovered
            , CountDeceased      #len(df_sim[df_sim['HealthStatus'] == 3])  # Dead
            , CountVaccinated
            , CountEffectiveVaccine
            , def_rows - CountNeverInfected                                 # Cumulative Sick 
            , CountDeceased # (already cumulative)                          # Cumulative Sick Dead
            , CountRecovered # (already cumulative)                         # Cumulative Sick Recovered
        ]

        # Append the row to the dataframe
        push!(df_trials, lst_row)

        # Also, check if we can interrupt the looping now.
        # If the number of sick people still circulating has fallen to 0
        # then we no longer have to loop - every subsequent day will have the same results as the current day

        #if len(df_sim[df_sim['HealthStatus'] == 1]) == 0:
        if length(df_sim[df_sim.DaysSick .== 0, "id"]) == nrow(df_sim)
            break
        end

    end

end

# Finally, save the results of the trials to a CSV file
outputfilename = @sprintf "output/trials_results_%s.csv" INITIAL_VACCINATION_RATE
CSV.write(outputfilename, df_trials);