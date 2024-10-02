using PowerModels; const _PM = PowerModels
using Ipopt, JuMP
using HiGHS, Gurobi, Juniper
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII ; const _PMTP = PowerModelsTopologicalActionsII  
using InfrastructureModels; const _IM = InfrastructureModels
using JSON
using Mosek, MosekTools

#######################################################################################
## Define solver ##
#######################################################################################

ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-4, "print_level" => 0)
highs = JuMP.optimizer_with_attributes(HiGHS.Optimizer)
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer)
set_optimizer_attribute(gurobi, "MIPGap", 1e-6)
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)
mosek = JuMP.optimizer_with_attributes(Mosek.Optimizer)

#######################################################################################
## Input data ##
#######################################################################################

#test_case = "case67.m"
test_case = "case39_acdc.m"
#test_case = "pglib_opf_case588_sdet_acdc.m"
#test_case = "case3120sp_mcdc.m"
#test_case = "cigre_b4_dc_grid.m"


#######################################################################################
## Parsing input data ##
#######################################################################################
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)

data_file = joinpath(@__DIR__,"data_sources",test_case)
data_original = _PM.parse_file(data_file)
data = deepcopy(data_original)
_PMACDC.process_additional_data!(data)

#for (g_id,g) in data["gen"]
#    g["cost"][1] = g["cost"][1]/10^4
#end 


for (l_id,l) in data["load"]
    if l_id != "4"
        l["pd"] = 0
        l["qd"] = 0
    else
        l["pd"] = l["pd"]*6
        l["qd"] = l["qd"]*6
    end
end


#######################################################################################
## Optimal Power Flow models ##
#######################################################################################
# OPF simulations
result_opf_ac = _PMACDC.run_acdcopf(data,ACPPowerModel,ipopt; setting = s)
result_opf_ac_lpac = _PMACDC.run_acdcopf(data,LPACCPowerModel,gurobi; setting = s)


#######################################################################################
## Busbar splitting models ##
#######################################################################################
# AC BS for AC/DC grid with AC switches state as decision variable. Creating deepcopies of the original dictionary as the grid topology is modified with busbar splitting
results = Dict{String,Any}()
results["ac"] = Dict{String,Any}()
results["lpac"] = Dict{String,Any}()

for i in 1:10
    #if i != 18
    print("Busbar $i split","\n")
    data_busbars_ac_split = deepcopy(data)
    splitted_bus_ac = i
    split_elements = _PMTP.elements_DC_busbar_split(data_busbars_ac_split)
    data_busbars_ac_split,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.DC_busbar_split_more_buses(data_busbars_ac_split,splitted_bus_ac)
    #ac_bs_ac = deepcopy(data_busbars_ac_split)
    #ac_bs_ac_ref = deepcopy(data_busbars_ac_split)
    #ac_bs_soc_ref = deepcopy(data_busbars_ac_split)
    #ac_bs_qc_ref = deepcopy(data_busbars_ac_split)
    ac_bs_lpac_ref = deepcopy(data_busbars_ac_split)

    #result_switches_AC_ac  = _PMTP.run_acdcsw_AC(ac_bs_ac,ACPPowerModel,juniper)

    #result_switches_AC_ac_ref  = _PMTP.run_acdcsw_AC_reformulation(ac_bs_ac_ref,ACPPowerModel,juniper)
    #result_switches_AC_soc_ref  = _PMTP.run_acdcsw_AC_reformulation(ac_bs_soc_ref,SOCWRPowerModel,gurobi)
    #result_switches_AC_qc_ref  = _PMTP.run_acdcsw_AC_reformulation(ac_bs_qc_ref,QCRMPowerModel,gurobi)
    #result_switches_AC_lpac_ref  = _PMTP.run_acdcsw_DC_reformulation(ac_bs_lpac_ref,LPACCPowerModel,gurobi)
    result_switches_AC_lpac_ref  = _PMTP.run_acdcsw_DC_reformulation(ac_bs_lpac_ref,ACPPowerModel,juniper)

    #try_ac_check = deepcopy(ac_bs_ac)
    #try_ac_check_orig = deepcopy(ac_bs_ac_ref)
    #try_ac_check_lpac = deepcopy(ac_bs_lpac_ref) 
    #try_ac_check_soc = deepcopy(ac_bs_soc_ref)
    #try_ac_check_qc = deepcopy(ac_bs_qc_ref)
    #prepare_AC_feasibility_check(result_switches_AC_ac_ref,data_busbars_ac_split,try_ac_check,switches_couples_ac,extremes_ZILs_ac)
    #prepare_AC_feasibility_check(result_switches_AC_lpac_ref,data_busbars_ac_split,try_ac_check_orig,switches_couples_ac,extremes_ZILs_ac)
    #result_opf_ac_check_ori = _PMACDC.run_acdcopf(try_ac_check_orig,ACPPowerModel,ipopt; setting = s)
    #result_opf_ac_check_lpac = _PMACDC.run_acdcopf(try_ac_check_lpac,ACPPowerModel,ipopt; setting = s)

    #results["ac"]["$i"] = Dict{String,Any}()
    #results["ac"]["$i"]["ac"] = deepcopy(result_switches_AC_ac_ref)
    #results["ac"]["$i"]["ac_check"] = deepcopy(result_opf_ac_check_ori)
    results["lpac"]["$i"] = Dict{String,Any}()
    results["lpac"]["$i"] = deepcopy(result_switches_AC_lpac_ref)
    #results["lpac"]["$i"]["ac_check"] = deepcopy(result_opf_ac_check_lpac)
    #end
end

results_dict_lpac = JSON.json(results)
folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Papers/Topological_actions/Results/Busbar_splitting"

open(joinpath(folder_results,"case_39/Results_lpac_screening_dc_bs.json"),"w" ) do f
    write(f,results_dict_lpac)
end


obj = []
for i in eachindex(results["lpac"])
    #print([i,results["lpac"][i]["objective"]],"\n")
    push!(obj,results["lpac"]["$i"]["objective"])
end

obj_no_NaN = []
for i in eachindex(obj)
    if !isnan(obj[i]) 
        push!(obj_no_NaN,obj[i])
    end
end
minimum(obj_no_NaN)
println(obj)

sort(obj_no_NaN)

for i in eachindex(obj)
    if obj[i] == 41838.371018701
        print(i," is minimum \n")
    elseif obj[i] == 2.121643540881109e6
        print(i," is second minimum \n")
        #=
    elseif obj[i] ==  370580.58699711575
        print(i," is 370580 \n")
    elseif obj[i] ==  370664.969377956
        print(i," is 370664 \n")
    elseif obj[i] ==  371471.58010675106
        print(i," is 371471 \n")
    =#
    end
end

#B = [(i, count(==(i), obj)) for i in unique(obj)]



data_busbars_ac_split = deepcopy(data)

# Selecting which busbars are split
splitted_bus_ac = 13
# -> this works!
#splitted_bus_ac = 37


split_elements = _PMTP.elements_AC_busbar_split(data)
data_busbars_ac_split,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_more_buses(data_busbars_ac_split,splitted_bus_ac)


ac_bs_ac_ref = deepcopy(data_busbars_ac_split)
ac_bs_lpac_ref = deepcopy(data_busbars_ac_split)

# One can select whether the branches originally linked to the split busbar are reconnected to either part of the split busbar or not
# Reconnect all the branches

result_switches_AC_lpac_ref  = _PMTP.run_acdcsw_AC_reformulation(ac_bs_lpac_ref,LPACCPowerModel,gurobi)
result_switches_AC_ac_ref  = _PMTP.run_acdcsw_AC_reformulation(ac_bs_ac_ref,ACPPowerModel,juniper)

results_bs_lpac = JSON.json(result_switches_AC_lpac_ref)
open(joinpath(folder_results,"case_39/Results_ac_bs_13_lpac.json"),"w" ) do f
    write(f,results_bs_lpac)
end
results_bs_ac = JSON.json(result_switches_AC_ac_ref)
open(joinpath(folder_results,"case_39/Results_ac_bs_13_ac.json"),"w" ) do f
    write(f,results_bs_ac)
end


print_connections_AC_switches(result_switches_AC_lpac_ref,ac_bs_lpac_ref)



try_ac_check = deepcopy(ac_bs_ac_ref)
try_ac_check_lpac = deepcopy(ac_bs_lpac_ref) 

print_connections_AC_switches(result_switches_AC_lpac_ref,ac_bs_lpac_ref)
print_connections_AC_switches(result_switches_AC_ac_ref,ac_bs_ac_ref)



function prepare_AC_feasibility_check(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict)
    orig_buses = length(input_dict["bus"]) # original bus length
    for (br_id,br) in result_dict["solution"]["switch"]
        if haskey(br,"ZIL") && br["ZIL"] == true
            if result_dict["solution"]["switch"][br_id]["status"] >= 0.9
                delete!(input_ac_check["bus"],"$(extremes_dict[br_id][2])")
            else
                delete!(input_ac_check["switch"],br_id)
            end
        end
    end
    for l in eachindex(switch_couples)
        if result_dict["solution"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] >= 0.9
            aux =  deepcopy(input_ac_check["switch"]["$(switch_couples["$l"]["t_sw"])"]["auxiliary"])
            orig = deepcopy(input_ac_check["switch"]["$(switch_couples["$l"]["t_sw"])"]["original"])
            if aux == "gen"
                input_ac_check["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
            elseif aux == "load"
                input_ac_check["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
            elseif aux == "convdc"
                input_ac_check["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
            elseif aux == "branch"                
                if input_ac_check["branch"]["$(orig)"]["f_bus"] > orig_buses && input_ac_check["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                    input_ac_check["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                elseif input_ac_check["branch"]["$(orig)"]["t_bus"] > orig_buses && input_ac_check["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                    input_ac_check["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                end
            end
        elseif result_dict["solution"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] <= 0.1
            switch_t = deepcopy(input_ac_check["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
            aux_t = switch_t["auxiliary"]
            orig_t = switch_t["original"]
            print([l,aux_t,orig_t],"\n")
            if result_dict["solution"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                delete!(input_ac_check["switch"],"$(switch_t["index"])")
            elseif result_dict["solution"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                if aux_t == "gen"
                    input_ac_check["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_ac_check["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                    print([l,aux_t,orig_t,input_ac_check["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                elseif aux_t == "load"
                    input_ac_check["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_ac_check["switch"]["$(switch_t["index"])"]["t_bus"])
                    print([l,aux_t,orig_t,input_ac_check["load"]["$(orig_t)"]["load_bus"]],"\n")
                elseif aux_t == "convdc"
                    input_ac_check["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_ac_check["switch"]["$(switch_t["index"])"]["t_bus"])
                    print([l,aux_t,orig_t,input_ac_check["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                elseif aux_t == "branch" 
                    if input_ac_check["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_ac_check["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                        input_ac_check["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_ac_check["switch"]["$(switch_t["index"])"]["t_bus"])
                        print([l,aux_t,orig_t,input_ac_check["branch"]["$(orig_t)"]["f_bus"]],"\n")
                    elseif input_ac_check["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_ac_check["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                        input_ac_check["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_ac_check["switch"]["$(switch_t["index"])"]["t_bus"])
                        print([l,aux_t,orig_t,input_ac_check["branch"]["$(orig_t)"]["t_bus"]],"\n")
                    end
                end
            end

            switch_f = deepcopy(input_ac_check["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
            aux_f = switch_f["auxiliary"]
            orig_f = switch_f["original"]
            print([l,aux_f,orig_f],"\n")
            if result_dict["solution"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                delete!(input_ac_check["switch"],"$(switch_t["index"])")
            else
                if aux_f == "gen"
                    input_ac_check["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_ac_check["switch"]["$(switch_f["index"])"]["t_bus"])
                    print([l,aux_t,orig_t,input_ac_check["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                elseif aux_f == "load"
                    input_ac_check["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_ac_check["switch"]["$(switch_f["index"])"]["t_bus"])
                    print([l,aux_t,orig_t,input_ac_check["load"]["$(orig_t)"]["load_bus"]],"\n")
                elseif aux_f == "convdc"
                    input_ac_check["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_ac_check["switch"]["$(switch_f["index"])"]["t_bus"])
                    print([l,aux_t,orig_t,input_ac_check["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                elseif aux_f == "branch"
                    if input_ac_check["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_ac_check["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                        input_ac_check["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_ac_check["switch"]["$(switch_f["index"])"]["t_bus"])
                        print([l,aux_t,orig_t,input_ac_check["branch"]["$(orig_t)"]["f_bus"]],"\n")
                    elseif input_ac_check["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_ac_check["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                        input_ac_check["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_ac_check["switch"]["$(switch_f["index"])"]["t_bus"])
                        print([l,aux_t,orig_t,input_ac_check["branch"]["$(orig_t)"]["t_bus"]],"\n")
                    end
                end
            end
        end
    end
end

prepare_AC_feasibility_check(result_switches_AC_ac_ref,data,try_ac_check,switches_couples_ac,extremes_ZILs_ac)
prepare_AC_feasibility_check(result_switches_AC_lpac_ref,data,try_ac_check_lpac,switches_couples_ac,extremes_ZILs_ac)


data_bs_lpac_check = JSON.json(try_ac_check_lpac)
open(joinpath(folder_results,"case_39/Data_ac_bs_13_lpac_check.json"),"w" ) do f
    write(f,data_bs_lpac_check)
end
data_bs_ac_check = JSON.json(try_ac_check)
open(joinpath(folder_results,"case_39/Results_ac_bs_13_ac_check.json"),"w" ) do f
    write(f,data_bs_ac_check)
end


result_opf_ac_check = _PMACDC.run_acdcopf(try_ac_check,ACPPowerModel,ipopt; setting = s)
result_opf_ac_check_lpac = _PMACDC.run_acdcopf(try_ac_check_lpac,ACPPowerModel,ipopt; setting = s)

results_bs_lpac_check = JSON.json(result_opf_ac_check_lpac)
open(joinpath(folder_results,"case_39/Results_ac_bs_13_lpac_check.json"),"w" ) do f
    write(f,results_bs_lpac_check)
end
results_bs_ac_check = JSON.json(result_opf_ac_check)
open(joinpath(folder_results,"case_39/Results_ac_bs_13_ac_check.json"),"w" ) do f
    write(f,results_bs_ac_check)
end


obj = []
for i in 1:39
    push!(obj,[i,results["lpac"]["$i"]["lpac"]["objective"]])
end
println(obj)