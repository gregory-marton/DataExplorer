% T = DataExplorer("examples/2026_daygenbyfuel.xlsx", Sheet=2);
% TODO: add DataExplorer("examples/2026_energy_peak_by_source.xlsx");

%{
% 311 Schema file. NOTE: this is not data, this is just the schema!
T = de_load("examples/311_ServiceRequest_2020-present_DataDictionary_Updated_2025.xlsx", ...
    Sheet="All Agencies Complaint<>Details");
% Replace "Department of" with "D." in Agency categorical labels (case-sensitive)
% Convert categories to cellstr, perform replace on category names
cats = strrep(string(categories(T.Agency)), "Department of", "D.");
T.Agency = categorical(T.Agency, categories(T.Agency), cats);
de_stacked_bars(T, "Agency", "Descriptor");
% DataExplorer(T);
HPD = de_load("examples/311_ServiceRequest_2020-present_DataDictionary_Updated_2025.xlsx", ...
    Sheet="HPD Complaint<>Details");
% This appears strange, but the reason the values are the same across
% BMPs is not that the data are corrupt, but that we're looking at the 
% data dictionary, the schema, not the actual complaint data themselves:
de_pareto_multiples(HPD, "BMP", "Descriptor"); 
de_pareto_multiples(HPD, "BMP", "Additional_Details");
DataExplorer(HPD);
%}

%{ 
T = de_load("examples/State_Tobacco_Related_Disparities_Dashboard_Data.csv"); 
T.FromTo = strcat(string(T.Comparing_FocusGroup_), " vs. ", string(T.To_ReferenceGroup_)); 
removevars(T, ["Comparing_FocusGroup_", "To_ReferenceGroup_"]);
DataExplorer(T);
%}

%{
% DataExplorer("examples/ncdd-202501-grd-scaled.nc");
T = de_stride_sample('examples/ncdd-202501-grd-scaled.nc', Variable='tmax', Verbose=false);
T.tmin = de_stride_sample('examples/ncdd-202501-grd-scaled.nc', Variable='tmin', Verbose=false).tmin;
T.tavg = de_stride_sample('examples/ncdd-202501-grd-scaled.nc', Variable='tavg', Verbose=false).tavg;
% Aggregate by grid cell: mean and std across all time steps
T_agg = groupsummary(T, {'longitude','latitude'}, {'mean','std'}, {'tmax','tmin','tavg'});
% Geo scatter per variable: color = temporal mean, size = temporal std
de_geoscatter(T_agg.longitude, T_agg.latitude, T_agg.mean_tmax, T_agg.std_tmax, ...
    ColorLabel='mean(tmax)', SizeLabel='std(tmax)', MinSize=5, MaxSize=150, ...
    ColorLim=[-15, 25], SizeLim=[0, 20], ...
    Title='tmax', Source='Climate Data January 2025');
de_geoscatter(T_agg.longitude, T_agg.latitude, T_agg.mean_tmin, T_agg.std_tmin, ...
    ColorLabel='mean(tmin)', SizeLabel='std(tmin)', MinSize=5, MaxSize=150, ...
    ColorLim=[-15, 25], SizeLim=[0, 20], ...
    Title='tmin', Source='Climate Data January 2025');
de_geoscatter(T_agg.longitude, T_agg.latitude, T_agg.mean_tavg, T_agg.std_tavg, ...
    ColorLabel='mean(tavg)', SizeLabel='std(tavg)', MinSize=5, MaxSize=150, ...
    ColorLim=[-15, 25], SizeLim=[0, 20], ...
    Title='tavg', Source='Climate Data January 2025');
%}

%{
T = de_load('examples/Prod_dataset.xlsx', 'Sheet', 'Data');
is_production_in_billions_of_btus = ...
    (extractBetween(string(T.MSN),3,5) == "PRB");
T = T(is_production_in_billions_of_btus, :);
T(T.StateCode == "US", :) = [];
T.StateCode(T.StateCode == "X3") = "GulfC";
T.StateCode(T.StateCode == "X5") = "WestC";
T(T.MSN == "TEPRB", :) = []; % Total
T.MSN(T.MSN == "B1PRB") = "RenDsl";
T.MSN(T.MSN == "BFPRB") = "BioFuel";
T.MSN(T.MSN == "BOPRB") = "OthrBio";
T.MSN(T.MSN == "CLPRB") = "Coal";
T.MSN(T.MSN == "NCPRB") = "NonCmb";
T.MSN(T.MSN == "PAPRB") = "Crude";
T.MSN(T.MSN == "REPRB") = "Renbl";
T.MSN(T.MSN == "WDPRB") = "Wood";
T.MSN(T.MSN == "WWPRB") = "Waste";
DataExplorer(T);
% Caption: We have traded Coal for Oil.
%}

% TODOs:
% DataExplorer("examples/City_of_Flint_Distribution_System_Monitoring_Data_(Expanded)_20260417.csv");
% FIADB_URBAN_ENTIRE_CSV.zip
% LLCP2024ASC.zip
% MA-2024.zip
% State_Tobacco_Related_Disparities_Dashboard_Data.csv

%{
% annual_aqi_by_county_2025.zip and annual_conc_by_monitor_2025.zip
% are together?
%DataExplorer("examples/annual_aqi_by_county_2025.zip");
%DataExplorer("examples/annual_conc_by_monitor_2025.zip");
AQI = de_load("examples/annual_aqi_by_county_2025.zip");
% Prepare value ladder columns in the requested order and compute MedianAQI per county/state
cols = ["GoodDays", "ModerateDays", "UnhealthyForSensitiveGroupsDays", ...
    "UnhealthyDays", "VeryUnhealthyDays", "HazardousDays"];
de_statebins(AQI, StateCol="State", CellRenderer="value_ladder", ...
    DataVariables=cols, ColorVariable="MedianAQI", Title="EPA Air Quality Index");
% plot MedianAQI against 
CBM = de_load("examples/annual_conc_by_monitor_2025.zip");
% the pm25, pm10 concentrations from CBM as a de_statebin ladder 
is_pm25 = CBM.ParameterName == "PM2.5 - Local Conditions";

CBM_pm25 = CBM(is_pm25, :);
disp(groupsummary(CBM_pm25, "StateName", "median", "ArithmeticMean"));
% TODO: make this by median instead of mean. 
% Reason: the mean values are completely unreasonable, 
% driven by outliers that appear to be errors. 
% Likely BUG: a bunch of values where 
%   CBM.ParameterName == "PM2.5 - Local Conditions" 
% are at or just shy of 1440 which is suspiciously the number of minutes 
% per day, and wildly out of range for PM2.5, so this is a test case for 
% anomaly detection.
de_statebins(CBM_pm25, StateCol="StateName", ColorVariable="ArithmeticMean",...
    Title="PM2.5 Particulates");
% What? lol. The data cut off alphabetically at California. Other states
% are just not in the file. 
%}

% minerals.pdf 	minerals.zip
% DataExplorer("examples/minerals.zip");
% TODO: convert CIF format to something readable.

W = de_load("~/Downloads/Wyzant History - Sheet1.csv", VariableNamesLine=8);
DataExplorer(W);