% T = DataExplorer("examples/2026_daygenbyfuel.xlsx", Sheet=2);

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
