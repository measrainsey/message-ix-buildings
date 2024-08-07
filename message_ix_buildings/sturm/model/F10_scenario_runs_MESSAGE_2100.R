
### WRAPPER FUNCTION

library(tidyverse)
library(readxl)
# require(devtools) # source code from github
# library(RCurl) # read file from github

run_scenario <- function(run, 
                         #scenario_name, 
                         sector, 
                         path_in, path_inputs, path_rcode, path_out, 
                         prices, 
                         file_inputs, #file_data_model, #file_scenarios,  
                         geo_level, geo_level_aggr, geo_levels, 
                         geo_level_report,
                         region_select,
                         yrs,
                         input_mode, 
                         mod_arch,
                         mod_new, mod_ren,
                         report_type, report_var){
  
  print(paste("Start scenario run: ", run, "_", sector))
  
  # Track time
  start_time <- Sys.time()
  
  # # LOAD SETTINGS FOR SCENARIO RUNS (names Rfiles)
  # runs <- read_csv(file.path(path_in, "scenarios.csv"))
  
  #### SCENARIO SETTINGS ####
  # r <- runs %>% filter(scenario_name == run) %>% select(scenario_id) %>% pull # scenario run
  # ssp_r <- paste0(runs[r,"ssp"]) # SSP 
  
  # # Regions settings
  # geo_level <- "region_bld" # Level for analysis
  # geo_level_aggr <- "region_gea" # Level for aggregation
  # geo_levels <- c(geo_level, geo_level_aggr)
  # 
  # # Temporal settings
  # #yrs <- seq(2015,2050,5)
  # yrs <- c(seq(2015,2060,5),seq(2070,2100,10))
  # #yrs <- c(2015, 2020, 2030, 2040, 2050)
  
  # Unit conversion
  u_EJ_GWa <- 31.71
  
  # SOURCE MODEL FUNCTIONS
  print("Load functions")
  source(file.path(path_rcode, "B00_functions.R"))
  source(file.path(path_rcode, "F01_inputs_all.R"))
  source(file.path(path_rcode, "F03_energy_demand.R"))
  source(file.path(path_rcode, "F04_constr_decision.R"))
  # source(file.path(path_rcode, "F05_renov_decision.R"))
  source(file.path(path_rcode, "F05_renov_switch_decision.R"))
  source(file.path(path_rcode, "F02_init_stock_dyn_fut.R"))
  source(file.path(path_rcode, "F06_stock_dyn_complete_rev.R"))
  # source(file.path(path_rcode, "R00_report_basic.R"))
  if ("STURM" %in% report_type) {source(file.path(path_rcode, "R00_report_basic.R"))}
  if ("MESSAGE" %in% report_type) {source(file.path(path_rcode, "R01_report_MESSAGE.R"))}
  if ("IRP" %in% report_type) {source(file.path(path_rcode, "R02_report_IRP.R"))}
  if ("NGFS" %in% report_type) {source(file.path(path_rcode, "R03_report_NGFS.R"))}
  source(file.path(path_rcode, "R05_report_NAVIGATE.R"))
  print("Functions loaded!")
  
  
  # LOAD INPUT DATA 
  
  if(input_mode == "rdata") {
    print("Load data - RData")
    
    basename <- paste("data_input", run, sector, sep="_")
    load(file.path(path_in, paste0(basename, ".RData")))  # 2100
    
    rm(basename)
    
    print("Data loaded!")
  }
  
  if(input_mode== "csv") {
    print("Load data - csv")
    
    # Source - input data
    d <- fun_inputs_csv(path_in, path_inputs, file_inputs, sector, run) #file_scenarios, 
    
    print("Data loaded!")
  }
  
  
  ## BUILD DATA MODEL
  print("Build data model")
  
  d <- fun_build_data_model(d, sector, geo_level, geo_level_aggr,geo_levels, region_select)
  
  print("Data model - built!")
  
  

  ## Energy prices (from MESSAGE)
  if(is.null(prices) == FALSE){
    price_en <- prices %>%
      mutate(price_en = lvl/all_of(u_EJ_GWa)) %>%
      mutate(region = substr(node,5,7)) %>%
      #mutate(region_gea = ifelse(region_gea == "LAM", "LAC", region_gea)) %>%
      mutate(fuel = commodity) %>%
      mutate(fuel = ifelse(commodity == "biomass", "biomass_solid", fuel)) %>%
      mutate(fuel = ifelse(commodity == "electr", "electricity", fuel)) %>%
      mutate(fuel = ifelse(commodity == "lightoil", "oil", fuel)) %>%
      filter(commodity != "d_heat") %>%
      filter(year %in% yrs) %>%
      select(region, year, fuel, price_en) %>%
      rename_at("region",~paste(substr(prices$node[1],1,3))) # rename region column based on R11/R12
    
    price_en <- d$geo_data %>% # use the most granular level for prices
      left_join(price_en) %>% # Join R11/R12 data
      select_at(c(paste(geo_level),"year","fuel","price_en"))
    
    rm(prices)
  }
  
  ## Energy prices (from external input data)
  if(is.null(prices) == TRUE){price_en <- d$price_en}
  
  
  ### RESIDENTIAL SECTOR
  
  if (sector == "resid") {
    
    # Initialize housing stock (fun)
    print(paste("Initialize scenario run", sector))
    
    lst_stock_init <- fun_stock_init_fut(sector,
                                         run,
                                         mod_arch,
                                         yrs,
                                         d$geo_data, geo_levels, geo_level,
                                         d$bld_cases_eneff, d$bld_cases_fuel,
                                         d$pop,
                                         d$hh_size, # used for residential
                                         d$floor_cap, # used for commercial
                                         d$ct_inc_cl,
                                         d$ct_eneff, d$ct_fuel_comb,
                                         d$stock_arch_base,
                                         d$shr_mat, d$shr_arch, d$shr_fuel_heat_base, d$shr_distr_heat,
                                         d$en_int_heat, d$en_int_cool,
                                         d$days_cool,
                                         d$eff_cool, d$eff_heat,
                                         d$en_sav_ren, 
                                         d$hours_heat, d$shr_floor_heat,
                                         d$hours_cool,d$shr_floor_cool,
                                         d$hours_fans,d$power_fans,
                                         d$shr_acc_cool,
                                         d$eff_hotwater,d$en_int_hotwater,
                                         en_int_others =NULL, # only for commercial
                                         d$shr_need_heat,
                                         price_en,
                                         report_var
                                         )
    
    
    # Extract dataframes from list
    stock_aggr = lst_stock_init$stock_aggr
    bld_det_age_i = lst_stock_init$bld_det_age_i
    #bld_eneff_age = lst_stock_init$bld_eneff_age
    #bld_det = lst_stock_init$bld_det
    
    report = lst_stock_init$report
    # if ("vintage" %in% report){bld_eneff_age = lst_stock_init$bld_eneff_age} # Not needed - already within the DF report
    # if ("energy" %in% report){en_stock = lst_stock_init$en_stock}
    # if ("material" %in% report){mat_stock = lst_stock_init$mat_stock}
    
    rm(lst_stock_init)
    
    print(paste("Initialize scenario run", sector, "- completed!"))
    
    # Loop over timesteps
    print(paste("Start scenario run", sector))
    
    for (i in 2:length(yrs)) {
      
      # Energy demand intensities - heating/cooling
      lst_en_i <- fun_en_sim(sector,
                             yrs, i,
                             d$bld_cases_fuel,
                             d$en_int_heat, d$en_int_cool,
                             d$days_cool,
                             d$eff_cool, d$eff_heat,
                             d$en_sav_ren,
                             d$hours_heat, d$shr_floor_heat,
                             d$hours_cool, d$shr_floor_cool,
                             d$hours_fans, d$power_fans,
                             d$shr_acc_cool,
                             d$hh_size,d$floor_cap,
                             price_en)
      
      # Extract dataframes from list
      en_m2_scen_heat = lst_en_i$en_m2_scen_heat
      en_m2_scen_cool = lst_en_i$en_m2_scen_cool
      en_hh_tot = lst_en_i$en_hh_tot
      # en_hh_tot_ren_init = lst_en_i$en_hh_tot_ren_init
      # en_hh_tot_ren_fin = lst_en_i$en_hh_tot_ren_fin
      rm(lst_en_i)
      
      # Energy demand intensities - hot water
      en_hh_hw_scen <- fun_hw_resid(yrs, i,
                                    d$bld_cases_fuel,
                                    d$hh_size,
                                    #ct_fuel_dhw,
                                    d$eff_hotwater, 
                                    d$en_int_hotwater,
                                    d$en_int_heat)
      
      # Market share - new construction options
      
      if(mod_new == "endogenous"){

        ms_new_i <- fun_ms_new(yrs,i,
                               d$bld_cases_fuel, d$ct_bld_age,
                               d$hh_size, d$floor_cap,
                               d$cost_invest_new_shell, d$cost_invest_new_heat,
                               d$cost_intang_new_shell, d$cost_intang_new_heat,
                               d$ct_fuel_excl_new, d$ct_fuel_excl_reg,
                               d$discount_new, d$heterog_new, d$lifetime_new,
                               en_hh_tot
                               
        )} else if(mod_new == "exogenous"){

        ms_new_i <- fun_ms_new_target(yrs,i,
                                      d$bld_cases_eneff, d$bld_cases_fuel, 
                                      d$ct_bld_age,
                                      d$shr_eneff_new, d$shr_fuel_heat_new
        )
        }       
        

      
      
      try(if(nrow(ms_new_i)==0) stop("Error in new construction calculation! Empty dataframe ms_new_i"))
      
      # Market share - renovation + fuel switches options
      
      if(mod_ren == "endogenous"){
        
        lst_ms_ren_sw_i <- fun_ms_ren_sw(yrs,i,
                                         d$bld_cases_fuel, d$ct_bld_age, d$ct_tenr, d$ct_fuel_comb,
                                         d$ct_ren_eneff, d$ct_ren_fuel_heat,
                                         d$hh_size, d$floor_cap,
                                         d$hh_tenure,
                                         d$cost_invest_ren_shell,d$cost_invest_ren_heat,
                                         d$cost_intang_ren_shell,d$cost_intang_ren_heat,
                                         d$ct_fuel_excl_ren,d$ct_fuel_excl_reg,
                                         d$discount_ren, d$heterog_ren, d$lifetime_ren,
                                         d$rate_ren_low, d$rate_ren_high, #ren_rate, 
                                         # en_hh_tot_ren_init,
                                         # en_hh_tot_ren_fin
                                         en_hh_tot)
        
        ms_ren_i = lst_ms_ren_sw_i$ms_ren_i
        rate_ren_i = lst_ms_ren_sw_i$rate_ren_i
        ms_sw_i = lst_ms_ren_sw_i$ms_sw_i
        rm(lst_ms_ren_sw_i)
        
      } else if(mod_ren == "exogenous"){
        
        # Market share - renovation options
        ms_ren_i <- fun_ms_ren_target(yrs,i,
                                      d$bld_cases_fuel, d$ct_bld_age,
                                      d$shr_eneff_ren,d$shr_fuel_heat_ren
        )
        
        # Market share - fuel switches
        ms_sw_i <- fun_ms_fuel_sw(yrs,i,
                                  d$bld_cases_fuel, d$ct_bld_age,
                                  d$shr_fuel_heat_sw
                                  #ms_fuel_sw_target
        )
        
        rate_ren_i = d$rate_ren %>% filter(year == yrs[i])
        
        }       
      
      
      try(if(nrow(ms_ren_i)==0) stop("Error in renovation calculation! Empty dataframe ms_ren_i"))
      try(if(nrow(ms_sw_i)==0) stop("Error in renovation calculation! Empty dataframe ms_sw_i"))
      
      # Stock turnover
      lst_stock_i <- fun_stock_dyn(sector,
                                   mod_arch,
                                   yrs,i,
                                   run, #ssp_r, # removed ssp dimension
                                   geo_level, geo_level_aggr,geo_levels,
                                   d$bld_cases_fuel, d$bld_cases_eneff, 
                                   d$ct_bld_age, d$ct_fuel_comb,
                                   d$hh_size, d$floor_cap,
                                   stock_aggr, bld_det_age_i, #bld_det, 
                                   #bld_eneff_age,
                                   d$prob_dem,
                                   #rate_ren_low, rate_ren_high, #ren_rate, 
                                   d$rate_switch_fuel_heat,
                                   #ms_new, ms_ren,
                                   ms_new_i, ms_ren_i, rate_ren_i,
                                   ms_sw_i,
                                   #shr_acc_cool, 
                                   d$shr_distr_heat, d$shr_need_heat,
                                   en_m2_scen_heat, en_m2_scen_cool,
                                   en_hh_hw_scen, 
                                   en_m2_hw_scen, d$en_int_others, # used only in commercial
                                   #en_stock,
                                   d$mat_int,
                                   #mat_stock,
                                   report_var,
                                   report
      )
      
      # Extract dataframes from list
      report = lst_stock_i$report
      #en_stock = lst_stock_i$en_stock
      #mat_stock = lst_stock_i$mat_stock
      #stock_eneff.df = lst_stock_i$stock_eneff.df
      stock_aggr = lst_stock_i$stock_aggr
      bld_det_age_i = lst_stock_i$bld_det_age_i
      #bld_det = lst_stock_i$bld_det
      #bld_eneff_age = lst_stock_i$bld_eneff_age
      #ms_new = lst_stock_i$ms_new
      #ms_ren = lst_stock_i$ms_ren
      rm(lst_stock_i)
      
    }
    
  }
  
  
  ### COMMERCIAL SECTOR
  
  if (sector == "comm") {
    
    # Initialize housing stock (fun)
    print(paste("Initialize scenario run", sector))
    
    lst_stock_init <- fun_stock_init_fut(sector,
                                         run,
                                         mod_arch,
                                         yrs,
                                         d$geo_data, geo_levels, geo_level,
                                         d$bld_cases_eneff, d$bld_cases_fuel,
                                         d$pop,
                                         hh_size=NULL, #hh_size, # used for residential
                                         d$floor_cap, # used for commercial
                                         d$ct_inc_cl,
                                         d$ct_eneff, d$ct_fuel_comb,
                                         d$stock_arch_base,
                                         d$shr_mat, d$shr_arch, d$shr_fuel_heat_base,d$shr_distr_heat,
                                         d$en_int_heat, d$en_int_cool,
                                         d$days_cool,
                                         d$eff_cool, d$eff_heat,
                                         d$en_sav_ren, 
                                         d$hours_heat, d$shr_floor_heat,
                                         d$hours_cool,d$shr_floor_cool,
                                         d$hours_fans,d$power_fans,
                                         d$shr_acc_cool,
                                         d$eff_hotwater,d$en_int_hotwater,
                                         d$en_int_others, # only for commercial
                                         d$shr_need_heat,
                                         price_en=NULL, # not used in commercial
                                         report_var
    )
    
    
    # Extract dataframes from list
    stock_aggr = lst_stock_init$stock_aggr
    bld_det_age_i = lst_stock_init$bld_det_age_i
    report = lst_stock_init$report
    #bld_det = lst_stock_init$bld_det
    #bld_eneff_age = lst_stock_init$bld_eneff_age
    #en_stock = lst_stock_init$en_stock
    #mat_stock = lst_stock_init$mat_stock
    rm(lst_stock_init)
    
    # Loop over timesteps
    print(paste("Start scenario run", sector))
    
    for (i in 2:length(yrs)) {
      
      # Energy demand intensities
      lst_en_i <- fun_en_sim(sector,
                             yrs, i,
                             d$bld_cases_fuel,
                             d$en_int_heat, d$en_int_cool,
                             d$days_cool,
                             d$eff_cool, d$eff_heat,
                             d$en_sav_ren,
                             d$hours_heat, d$shr_floor_heat,
                             d$hours_cool, d$shr_floor_cool,
                             d$hours_fans, d$power_fans,
                             d$shr_acc_cool,
                             hh_size=NULL, # not used for commercial
                             d$floor_cap, 
                             price_en=NULL # not used for commercial
      )
      

      
      # Extract dataframes from list
      en_m2_scen_heat = lst_en_i$en_m2_scen_heat
      en_m2_scen_cool = lst_en_i$en_m2_scen_cool
      ## Additional output not needed for commercial
      # en_hh_tot = lst_en_i$en_hh_tot # 
      # en_hh_tot_ren_init = lst_en_i$en_hh_tot_ren_init
      # en_hh_tot_ren_fin = lst_en_i$en_hh_tot_ren_fin
      
      # Energy demand intensities - hot water
      en_m2_hw_scen <- fun_hw_comm(yrs, i,
                                   d$bld_cases_fuel, 
                                   d$eff_hotwater,
                                   d$en_int_hotwater
      )
  
      
      # Market share - new construction options
      ms_new_i <- fun_ms_new_target(yrs,i,
                                    d$bld_cases_eneff, d$bld_cases_fuel, 
                                    d$ct_bld_age,
                                    d$shr_eneff_new, d$shr_fuel_heat_new
      )       
      
      # Market share - renovation options
      ms_ren_i <- fun_ms_ren_target(yrs,i,
                                    d$bld_cases_fuel, d$ct_bld_age,
                                    d$shr_eneff_ren,d$shr_fuel_heat_ren
      )
      
      # Market share - fuel switches
      ms_sw_i <- fun_ms_fuel_sw(yrs,i,
                                d$bld_cases_fuel, d$ct_bld_age,
                                d$shr_fuel_heat_sw
                                #ms_fuel_sw_target
      )
      
      rate_ren_i = d$rate_ren %>% filter(year == yrs[i])
      
      
      
      # Stock turnover
      lst_stock_i <- fun_stock_dyn(sector,
                                   mod_arch, # mod_arch = "new", mod_arch = "stock"
                                   yrs,i,
                                   run, #ssp_r,
                                   geo_level, geo_level_aggr,geo_levels,
                                   d$bld_cases_fuel, d$bld_cases_eneff, 
                                   d$ct_bld_age, d$ct_fuel_comb,
                                   hh_size = NULL, # Not used for commercial
                                   d$floor_cap,
                                   stock_aggr, bld_det_age_i, #bld_det, 
                                   #bld_eneff_age, # keep track of age
                                   d$prob_dem,
                                   #rate_ren_low, rate_ren_high, #ren_rate,
                                   d$rate_switch_fuel_heat,
                                   #ms_new, ms_ren,
                                   ms_new_i, ms_ren_i, rate_ren_i,
                                   ms_sw_i,
                                   #shr_acc_cool, 
                                   d$shr_distr_heat, d$shr_need_heat,
                                   en_m2_scen_heat, en_m2_scen_cool,
                                   en_hh_hw_scen, en_m2_hw_scen, d$en_int_others,
                                   #en_stock,
                                   d$mat_int,
                                   #mat_stock,
                                   report_var,
                                   report)
      
      
      # Extract dataframes from list
      report = lst_stock_i$report
      #en_stock = lst_stock_i$en_stock
      #mat_stock = lst_stock_i$mat_stock
      #stock_eneff.df = lst_stock_i$stock_eneff.df
      stock_aggr = lst_stock_i$stock_aggr
      bld_det_age_i = lst_stock_i$bld_det_age_i
      #bld_det = lst_stock_i$bld_det
      #bld_eneff_age = lst_stock_i$bld_eneff_age
      #ms_new = lst_stock_i$ms_new
      #ms_ren = lst_stock_i$ms_ren
      rm(lst_stock_i)
      
    }
    
  }
  
  ### REPORTING ###
  
  ## MESSAGE report -  Aggregate results for reporting
  if ("MESSAGE" %in% report_type) {output <- fun_report_MESSAGE(sector, report_var, report, d$geo_data, geo_level, geo_level_report)}

  ## STURM basic report (results written as csv)
  if ("STURM" %in% report_type) {fun_report_basic(report, report_var, d$geo_data, geo_level, geo_level_report, sector, run, path_out)}
    
  ## Report results - IRP template (results written as csv)
  if ("IRP" %in% report_type) {fun_report_IRP(report, report_var, d$geo_data, geo_level, geo_level_report, sector, run, yrs, path_out)}
  
  ## Report results - NGFS template (results written as csv)
  if ("NGFS" %in% report_type) {fun_report_NGFS(report, report_var, d$geo_data, geo_level, geo_level_report, sector, run, yrs, path_out)}
  
  ## Report results - NGFS template (results written as csv)
  if ("NAVIGATE" %in% report_type) {fun_report_NAVIGATE(report, report_var, d$geo_data, geo_level, geo_level_report, sector, run, yrs, path_out)} # path_in, ct_bld, ct_ren_eneff, ren_en_sav_scen # currently not used
  
  # Tracking time
  end_time <- Sys.time()
  print(paste("Time to run script 04_run_future: ",end_time - start_time))
  print(paste0("Start: ", start_time))
  print(paste0("End: ",end_time))
  rm(start_time, end_time)
  
  print("scenario run completed!")
  
  #return(en_stock)
  if ("MESSAGE" %in% report_type) {return(output)} 

}
