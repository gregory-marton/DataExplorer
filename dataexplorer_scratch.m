%{ 
T = SampleData("examples/State_Tobacco_Related_Disparities_Dashboard_Data.csv"); 
T.FromTo = strcat(string(T.Comparing_FocusGroup_), " vs. ", string(T.To_ReferenceGroup_)); 
removevars(T, ["Comparing_FocusGroup_", "To_ReferenceGroup_"]);
DataExplorer(T);
%}

% T = DataExplorer("examples/2026_daygenbyfuel.xlsx", Sheet=2);