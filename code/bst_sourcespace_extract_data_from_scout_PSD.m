[file,path]=uigetfile('*.mat');

cd(path)

Data=load(file);
Data.Value(:,2)=[];


%Get startFreq and endFreq 

    inputs = {'Number of Frequencies', 'Number of Regions'};
    defaults = {'6', '4'};	
    answer = inputdlg(inputs, 'Please Input Parameters', 2, defaults, 'on');
    [NumFreq,NumReg] = deal(answer{:});
    NumFreq =str2num(NumFreq);
    NumReg =str2num(NumReg);
  
Interval=NumFreq*NumReg;



% First_names=Data.Description(1:Interval:end);
% First_names_org=[First_names(3:3:end) First_names(1:3:end) First_names(2:3:end)];
% 
% 
% slashindex=strfind(First_names{1},'/');
% spaceindex=strfind(First_names{1},' ');
% 
% for i=1:length(First_names)
% 
%     slashindex=strfind(First_names{i},'/');
%     spaceindex=strfind(First_names{i},' ');
% 
%     
%     names(i,:)=First_names{i}(slashindex(1)+1:slashindex(1)+10);
%     region(i,:)=First_names{i}(1:spaceindex(1)-1);
%     freq_band(i,:)=First_names{i}(spaceindex(end)+1:end);
% end


for i=1:Interval
    if i==1
        All_Description=Data.Description(i:Interval:end);
        All_Data=Data.Value(i:Interval:end);
    else
        All_Description=[All_Description,Data.Description(i:Interval:end)];
        All_Data=[All_Data,Data.Value(i:Interval:end)];
    end
end

All_Names=All_Description;
All_Region=All_Description;
All_freq_band=All_Description;


 for i=1:length(Data.Description)
    slashindex=strfind(All_Description{i},'/');
    spaceindex=strfind(All_Description{i},' ');
    
    All_Names{i}=All_Description{i}(slashindex(1)+1:slashindex(1)+10);
    All_Region{i}=All_Description{i}(1:spaceindex(1)-1);
    All_freq_band{i}=All_Description{i}(spaceindex(end)+1:end);
 end
 
 All_Region_Freq=strcat(All_Region,All_freq_band);

%Check that names match
for a=1:size(All_Names,1)
    for b=1:size(All_Names,2)-1
            if ~isequal(All_Names{a,b},All_Names{a,b+1})
            fprintf('ERROR: Names Dont Match in row')
            end
    end
end

%Check regions and freq match
for a=1:size(All_Region_Freq,2)
    for b=1:size(All_Region_Freq,1)-1
            if ~isequal(All_Region_Freq{b,a},All_Region_Freq{b+1,a})
            fprintf('ERROR: Regions/Frequencies Dont Match in column')
            end
    end
end

Final_table=array2table(All_Data,'VariableNames',All_Region_Freq(1,:),'RowNames',All_Names(:,1))
