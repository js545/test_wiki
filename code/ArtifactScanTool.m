%PURPOSE:           1) Extract ArtifactScan information from PDG file
%                   2) Decide which channels should be entirely removed
%                       from data averaging
%                       -Channels with average signal under 64
%                       automatically rejected
%                       -Calculate median, mean, group MAD of amplitude and gradient for every
%                           channel (collapsed across trials)
%                       -Several channel removal options
%                       -Continuous heatmap graphing
%                       -2D sensor label mapping
%                   4) Determine the best cutoff value for both amplitude and gradient
%                       -BESA excludes trials that contain an amp OR grad
%                       value above the cutoff in just 1 channel
%                   5) Display the distribution of amplitude and gradient
%                       for all trials (for visual confirmation)
%                   6) Show how many trials will be lost in each condition
%                       based on proposed cutoff
%                   7) Save directly to .PDG and .bad files
%
%
%INPUT:             Prereq: MATLAB R2018b or later
%                   1) Batch run artifactscan in BESA
%                   2) Have an ALL condition setup in paradigm
%                   3) Run this script
%OUTPUT:            1) Gradient Plot during channel removal
%                   2) Histograms for the distribution of trials by both
%                       amplitude and gradient with suggested cutoff values
%                   3) Updated .PDG and .bad files
%                   4) Log csv file with sub, channels removed, cutoff
%                       values, trials accepted for each condition
%AUTHOR:            Nick Christopher-Hayes
%Acknowledgments:   Tony Wilson, Alex Wiesman, Christine Embury, Brandon Lew, Rachel Spooner
%VERSION HISTORY:   01/06/2020  v1: First working version


function ArtifactScanTool(userCondition)
%error('Im undergoing some minor edits. Please check back in 1-2 days :)');
% GET GENERIC PROJECT/SUBJECT/FILE INFO %

% check if user entered anything %
switch nargin
    case 1
        userCondition = userCondition;
    otherwise
        error('You did not enter a condition input argument!');
end



% project directory %
filedirs=uigetdir2;
if length(filedirs)==1
    allDirs = genpath(filedirs{1});
    allDirs = regexp(allDirs, ';', 'split');
    allDirs(ismember(allDirs,{''})) = [];
    % for all directories under the parent directory %
else
    allDirs=filedirs;
end
% allDirs = {'\\Bt137863\D\Infant\S002\Right Hand'};
% allDirs = {'C:\Users\chrnic2\Desktop\testytesttest'};

for d = 1:length(allDirs)
    % all PDG files for a directory %
    paradigmFileInfo = dir(fullfile(allDirs{d}, '*.PDG'));
    % skip hidden directories %
    if contains(allDirs{d}, '.')
        continue
    % visible directory that found a PDG file %
    elseif length(paradigmFileInfo) >= 1
        for f = 1:length(paradigmFileInfo)
            subID = regexp(paradigmFileInfo(f).folder, '\', 'split');
            subID = subID{end};
            newFNameRoot = split(paradigmFileInfo(f).name, '.');
            
            display_text_sub = sprintf('Subject: %s\n\n',subID);
            % open original file, store content, and close the file%
            pdgFile = fopen(fullfile(paradigmFileInfo(f).folder, paradigmFileInfo(f).name), 'r');
            %pdgFileContent = fileread(fullfile(paradigmFileInfo(f).folder, paradigmFileInfo(f).name));
            pdgFileContent = textscan(pdgFile,'%s','delimiter','\n');
            fclose(pdgFile);
            
            % check that artifact scan section of code exists in PDG file
            % before moving on %
            if find(strcmp(pdgFileContent{1,1},'[ArtifactScan]')) > 0
                % create the file index to guide searching %
                ArtifactScanIndex = find(strcmp(pdgFileContent{1,1},'[ArtifactScan]'));
            else
                fprintf("No artifact scan found in PDG file: %s\n", paradigmFileInfo(f).name);
                continue
            end
            
            % check that a bad file exists %
            if exist(fullfile(paradigmFileInfo(f).folder, sprintf("%s.bad", newFNameRoot{1})), 'file') == 0
               error("You don't have a .bad file to append bad channels to. That's a requirement of this script.");
            end

            % setup condition labels and indeces %
            ConditionsStartIndex = find(strcmp(pdgFileContent{1,1},'[Names]'));
            ConditionsEndIndex = find(strcmp(pdgFileContent{1,1},'[Epochs]'));
            allConditions = split(pdgFileContent{1}(ConditionsStartIndex+1:ConditionsEndIndex-2));
            if size(pdgFileContent{1}(ConditionsStartIndex+1:ConditionsEndIndex-2), 1) == 0
                error("No conditions found in PDG");
            elseif size(pdgFileContent{1}(ConditionsStartIndex+1:ConditionsEndIndex-2), 1) == 1
                allConditions = allConditions';
            end


            % check if user-entered condition exists, if not, end program %
            if ismember(1,strcmp(allConditions(:,1),userCondition)) ~= 1
                error('You did not enter a valid condition! You seem to have gotten lost in the sauce...');
            end
            

            % NOTES REGARDING FILE STRUCTURE %
            % 1) Bad channels at line 2, values > 0; tab delimited
            %       -Access Option 1
            %       dlmread(fullfile(paradigmFileInfo(f).folder,paradigmFileInfo(f).name),'\t',[ArtifactScanIndex+1 0 ArtifactScanIndex+1 333])'
            %       -Access Option 2
            %       bad_channels = regexp(pdgFileContent{1}(ArtifactScanIndex+2), '\t', 'split');
            %       bad_channels = str2double(bad_channels{1}(1:334));
            %       -Option 3 (Used here)
            %       Do not access previously defined bad channels, but instead
            %       define them with this script
            % 2) After first 4 lines following ArtifactScan Index, groups of 4 lines
            %   -Amplitude Range values at line 6
            %   -Gradient Range values at line 8
            %   -Columns 1-204(planar gradiometers)
            %   -Col 205-306 (magnetometers)
            %   -Col 307-334 (miscellaneous)
            % 3) Time is stored in microseconds

             % check which sensor type to use %
            sensor_type = questdlg('What type of sensors?','Sensor Type','GRADs','MAGs','GRADs');
            if strcmp(sensor_type,'GRADs')
                sensor_range = [1 204];
                heatmap_fixed_vals = [1300, 200, 800, 100];
                channel_labels = ast_bad_channel_mapper(sensor_range);
            elseif strcmp(sensor_type,'MAGs')
                sensor_range = [205 306];
                heatmap_fixed_vals = [4000, 600, 2500, 300];
                channel_labels = ast_bad_channel_mapper(sensor_range);
            else
                error('Sensor Type Not Selected!');
            end
            
            % Low signal Value
            lowSigValue=64;
            
            
            % create bad channel annotation row of 0's (nothing is bad yet), and
            % labels to go along
            bad_channels = zeros(1,sensor_range(2)-sensor_range(1)+1);
            channel_numbers = 1:size(bad_channels,2);
            

            % store amplitude and gradient data in separate variables %
            all_amp_data = pdgFileContent{1}(ArtifactScanIndex+6:4:size(pdgFileContent{1},1));
            all_amp_data = str2double(split(all_amp_data(:)));
            all_grad_data = pdgFileContent{1}(ArtifactScanIndex+8:4:size(pdgFileContent{1},1));
            all_grad_data = str2double(split(all_grad_data(:)));
            all_grad_data_combined_conds_epochs = pdgFileContent{1}(ArtifactScanIndex+5:4:size(pdgFileContent{1},1));
            all_grad_data_combined_conds_epochs = str2double(split(all_grad_data_combined_conds_epochs));
            all_amp_data = all_amp_data(:,1:end-1);
            all_grad_data = all_grad_data(:,1:end-1);
            channel_numbers_orig_size = size(all_amp_data,2);
            
            if (size(all_amp_data,2) == size(channel_numbers,2))
                all_amp_data = [all_grad_data_combined_conds_epochs, all_amp_data];
                all_grad_data = [all_grad_data_combined_conds_epochs, all_grad_data];
            elseif size(all_amp_data,2) >= 307
                all_amp_data = [all_grad_data_combined_conds_epochs, all_amp_data(:, sensor_range(1):sensor_range(2))];
                all_grad_data = [all_grad_data_combined_conds_epochs, all_grad_data(:, sensor_range(1):sensor_range(2))];
            else
                error('Sensor counts vs selected sensor types do not match.');
            end

            % create extra column labels %
            %   -1 and 2 are the asci values for letters i(condition index) and t (time/epoch)
            % merge all the data and sort it by time %
            all_amp_data = [55573,55116,channel_numbers;55573,55116,bad_channels;all_amp_data];
            all_grad_data = [55573,55116,channel_numbers;55573,55116,bad_channels;all_grad_data];
            all_amp_data = sortrows(all_amp_data,2);
            all_grad_data = sortrows(all_grad_data,2);

            % Sometimes BESA is stupid and doesn't map condition labels-to-numbers properly. %
            % Therefore, we re-assign the condition name labels to the unique condition %
            % numbers that appear in the artifact data... YES, BESA sucks %

            unique_condition_numbers = unique(all_amp_data(3:end,1));
            
            allConditions = [allConditions(ismember(str2double(string(allConditions(:,2))),unique_condition_numbers)),num2cell(unique_condition_numbers)];
            
            try
                userConditionNum = allConditions{strcmp(userCondition,allConditions(:,1)),2};
            catch
                fprintf('Unfortunately, BESA is not creating an artifact scan for the input condition.\n')
                fprintf('Your problem could be one of the following:\n');
                fprintf('1) You may have too many conditions in your paradigm\n');
                fprintf('2) The condition you entered had too many trials\n');
                fprintf('3) The condition you entered is a combination of two other conditions\n');
                fprintf('4) The condition you entered was not calculated because the max number of trials was reached\n');
                fprintf('You can either:\n');
                fprintf('1) Simplify your paradigm to less conditions and re-run artifact scan');
                fprintf('2) Enter a different condition into the input parameter');
                fprintf('3) Rearrange your paradigm so that your conditions of interest are at the top (and therefore are more likely to be calculated)');
                error('BESA saieed Nuh uhhh!');
            end
            
            user_input_cycle = {''};
            while user_input_cycle{1} ~= "end"
                lowSigWarning = 'False';

                % create an initial 'sort by all' condition %
                filter_amp_data_Condition = ast_condition_sort(all_amp_data, userConditionNum);
                filter_grad_data_Condition = ast_condition_sort(all_grad_data, userConditionNum);

                % REMOVING CHANNELS %

                %Set the min and max heatmap values %
               
                amp_heatmap_max = median(median(filter_amp_data_Condition(:,3:end),2))+(5*mad(median(filter_amp_data_Condition(:,3:end),2),1));
                if amp_heatmap_max <= 200
                    amp_heatmap_max = heatmap_fixed_vals(1);
                end
                
                amp_heatmap_min = median(median(filter_amp_data_Condition(:,3:end),2))-(5*mad(median(filter_amp_data_Condition(:,3:end),2),1));
                if amp_heatmap_min < 0
                    amp_heatmap_min = 0;
                end
                
                grad_heatmap_max = median(median(filter_grad_data_Condition(:,3:end),2))+(5*mad(median(filter_grad_data_Condition(:,3:end),2),1));
                if grad_heatmap_max <= 100
                    grad_heatmap_max = heatmap_fixed_vals(3);
                end
                
                grad_heatmap_min = median(median(filter_grad_data_Condition(:,3:end),2))-(5*mad(median(filter_grad_data_Condition(:,3:end),2),1));
                if grad_heatmap_min < 0
                    grad_heatmap_min = 0;
                end
            
                display_text_channel = sprintf(['%s     ###      INFORMATION PROMPT      ###\nDecide which channels will be identified as bad.\n'...
                    'Low signal channels will automatically be removed regardless of channel exclusion method.\n\n'], display_text_sub);

                % CONSISTENCY method #1: (Subject_channels_Mean) > (Group_Mean + 3*Group_STDEV) %
                display_text_channel_consistency_mean = sprintf('   ~~~ MEAN METHOD (DEFAULT) ~~~   \n\n');
                display_text_channel_consistency_mean = sprintf(['%s A Channel is flagged if:\n 1) It has a mean (amplitude & gradient) ' ...
                'X number of STDEVs beyond the mean for all channels\n\n'], display_text_channel_consistency_mean);

                % CONSISTENCY method #2: (Subject_channels_Median) > (Group_Median + 3*Group_MAD) %
                display_text_channel_consistency_median = sprintf('   ~~~ MEDIAN METHOD ~~~   \n\n');
                display_text_channel_consistency_median = sprintf(['%s A Channel is flagged if:\n 1) It has a median (amplitude & gradient) '...
                    'X number of MADs beyond the median for all channels\n\n'], display_text_channel_consistency_median);

                % MIXED method #1: VARIABILITY OR CONSISTENCY method #1 %
                display_text_channel_mixed_mean = sprintf('   ~~~ MIXED MEAN METHOD ~~~   \n\n');
                display_text_channel_mixed_mean = sprintf(['%s A Channel is flagged if: \n1) It has a mean (amplitude & gradient) '...
                    'X number of STDEVs beyond the mean for all channels\nOR\n2) It has a STDEV (amplitude & gradient) X number of STDEVs beyond the mean STDEV for all channels ###\n\n'], display_text_channel_mixed_mean);

                % MIXED method #2: VARIABILITY OR CONSISTENCY method #2 %
                display_text_channel_mixed_median = sprintf('   ~~~ MIXED MEDIAN METHOD ~~~   \n\n');
                display_text_channel_mixed_median = sprintf(['%s A Channel is flagged if: \n1) It has a median (amplitude & gradient) '...
                    'X number of MADs beyond the median for all channels\nOR\n2) It has an MAD (amplitude & gradient) X number of MADs beyond the median MAD for all channels ###\n\n'], display_text_channel_mixed_median);

                % VARIABILITY method: (Subject_channels_MAD) > (Group_MAD_MEDIAN + 3*Group_MAD) %
                display_text_channel_variability = sprintf('   ~~~ VARIABILITY METHOD ~~~   \n\n');
                display_text_channel_variability = sprintf(['%s A Channel is flagged if:\n 1) It has an MAD (amplitude & gradient) '...
                    'X number of MADs beyond the median MAD for all channels\n\n'], display_text_channel_variability);

                % original with prompt for variablility method
                %waitfor(msgbox(sprintf("%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n\nClick OK to proceed", display_text_channel, display_text_channel_consistency_mean, ...
                 %   display_text_channel_consistency_median, display_text_channel_mixed_mean, display_text_channel_mixed_median, display_text_channel_variability),'Channel Exclusion Methods', 'replace'));
                
                % absent of variablility method in prompt
                waitfor(msgbox(sprintf("%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n\nClick OK to proceed", display_text_channel, display_text_channel_consistency_mean, ...
                    display_text_channel_consistency_median),'Channel Exclusion Methods', 'replace'));

                diag_options.WindowStyle = 'normal';
                diag_options.Interpreter = 'tex';

                cons_method_1_version_counter = 1;
                cons_method_2_version_counter = 1;
                mix_method_1_version_counter = 1;
                mix_method_2_version_counter = 1;
                var_method_version_counter = 1;

                % Plot Sensor Array for Reference %
                meg_sensor_array_fig = figure('Name','MEG Sensor Array','NumberTitle','off', 'Position', [100 300 400 200]);
                %'Position', [1350 575 500 400]
                cfg = []; cfg.layout = 'neuromag306planar.lay'; layout = ast_prepare_layout(cfg); ast_plot_layout(layout);

                
                % starts main display loop%
                user_input_bad_channel_method = {''};
                while user_input_bad_channel_method{1} ~= "end"
                    user_input_method = questdlg('Which channel exclusion method would you like to use?','CHANNEL EXCLUSION METHOD','MEAN','MEDIAN','MANUAL','MEAN');
                    if strcmp(user_input_method,'MEAN') user_input_method = "mean"; elseif strcmp(user_input_method,'MEDIAN') user_input_method = "median"; ...
                    elseif strcmp(user_input_method,'MANUAL') user_input_method = "manual"; end

                    % force correct input %
                    while user_input_method ~= "mean" && user_input_method ~= "median" && user_input_method ~= "manual"
                        user_input_method = questdlg('Which channel exclusion method would you like to use?','CHANNEL EXCLUSION METHOD','MEAN','MEDIAN','MANUAL','MEAN');
                        if strcmp(user_input_method,'MEAN') user_input_method = "mean"; elseif strcmp(user_input_method,'MEDIAN') user_input_method = "median"; ...
                        elseif strcmp(user_input_method,'MANUAL') user_input_method = "manual"; end
                    end
                    
                    
                    chanAmpDevThreshold = 0;
                    chanGradDevThreshold = 0;
                    
                    % Manual method %
                    if user_input_method{1} == "manual"
                        ast_channel_selection_method = "manual";
                        bad_channels_to_be_removed = inputdlg('Enter channel numbers separated by commas (e.g.   MEG2642,MEG2643)', 'User-defined bad channels', 2, {'MEG2643'}, diag_options);
                        bad_channels_to_be_removed = split(bad_channels_to_be_removed, ',');
                        bad_channels_to_be_removed_returned = find(ismember(channel_labels, bad_channels_to_be_removed));
                        
                        % force correct input %
                        while size(bad_channels_to_be_removed,1) ~= size(bad_channels_to_be_removed_returned,1)
                            bad_channels_to_be_removed = inputdlg('Not all channels you entered exist, please try again.\n\nEnter channel numbers separated by commas (e.g.   MEG2643)', ...
                                'User-defined bad channels', 2, {'MEG2643'}, diag_options);
                        end

                        bad_channels_to_be_removed = transpose(bad_channels_to_be_removed_returned);
                        [all_amp_data_bad_chnls_removed, all_grad_data_bad_chnls_removed] = ast_manual_remove_bad_channels(all_amp_data, all_grad_data, channel_numbers, bad_channels_to_be_removed);
                        
                        msgbox_name = 'Progress Report: MANUAL METHOD';
                        amp_fig_name = 'Amplitude_Heatmap_MANUAL_METHOD';
                        grad_fig_name = 'Gradient_Heatmap_MANUAL_METHOD';
                        
                        display_text_channel_changed = sprintf('%sLow Signal Cutoff: %.1f\n\n', sprintf("%s\n%s", display_text_channel), lowSigValue);
                        
                        channel_amp_data_Cutoff_logical = logical(bad_channels);
                        channel_grad_data_Cutoff_logical = logical(bad_channels);
                        low_sig_range_all_channels_val_logical = logical(bad_channels);
                    
                    
                    % else it's a statistical method %
                    else
                    
                        chanDevThresholds = inputdlg({'Enter a new amplitude deviation cutoff: ', 'Enter a new gradient deviation cutoff: '}, 'Deviation cutoff', 2, {'4','8'}, diag_options);
                        chanAmpDevThreshold = str2double(chanDevThresholds{1});
                        chanGradDevThreshold = str2double(chanDevThresholds{2});
                        % force correct input %
                        while isnan(chanAmpDevThreshold) | isnan(chanGradDevThreshold)
                            chanDevThresholds = inputdlg({'Enter a new amplitude deviation cutoff: ', 'Enter a new gradient deviation cutoff: '}, 'Deviation cutoff', 2, {'4','8'}, diag_options);
                            chanAmpDevThreshold = str2double(chanDevThresholds{1});
                            chanGradDevThreshold = str2double(chanDevThresholds{2});
                        end
                        
                        
                        % CONSISTENCY methods %
                        if user_input_method{1} == "mean" || user_input_method{1} == "median"
                            
                            %determine bad channels
                            [channel_amp_data_Cutoff_logical, channel_grad_data_Cutoff_logical, low_sig_range_all_channels_val_logical] = ...
                            ast_remove_bad_channels_consistency_formula(filter_amp_data_Condition, filter_grad_data_Condition, chanAmpDevThreshold, chanGradDevThreshold, user_input_method{1}, lowSigValue);

                            if sum(low_sig_range_all_channels_val_logical) > 0
                               warndlg(sprintf("WARNING: You have %.1f channels identified with low signal (i.e. low signal existed in more than 10%% of your trials). Best to check yo data!", ...
                                            sum(low_sig_range_all_channels_val_logical)));
                               lowSigWarning = 'True';
                            end

                            if user_input_method{1} == "mean"
                                ast_channel_selection_method = "mean";
                                
                                %collect text for display
                                display_text_channel_changed = sprintf('%sAmplitude deviation Cutoff: %.1f \nGradient deviation Cutoff: %.1f\nLow Signal Cutoff: %.1f\n\n', ...
                                                                          sprintf("%s\n%s", display_text_channel, display_text_channel_consistency_mean), chanAmpDevThreshold, chanGradDevThreshold, lowSigValue);

                                msgbox_name = 'Progress Report: MEAN METHOD';
                                amp_fig_name = sprintf('Amplitude_Heatmap_MEAN_METHOD_v%d', round(cons_method_1_version_counter));
                                grad_fig_name = sprintf('Gradient_Heatmap_MEAN_METHOD_v%d', round(cons_method_1_version_counter));

                                cons_method_1_version_counter = cons_method_1_version_counter+1;
                            elseif user_input_method{1} == "median"
                                ast_channel_selection_method = "median";
                                %collect text for display
                                display_text_channel_changed = sprintf('%sAmplitude deviation Cutoff: %.1f \nGradient deviation Cutoff: %.1f\nLow Signal Cutoff: %.1f\n\n', ...
                                                                          sprintf("%s\n%s", display_text_channel, display_text_channel_consistency_median), chanAmpDevThreshold, chanGradDevThreshold, lowSigValue);


                                msgbox_name = 'Progress Report: MEDIAN METHOD';
                                amp_fig_name = sprintf('Amplitude_Heatmap_MEDIAN_METHOD_v%d', round(cons_method_2_version_counter));
                                grad_fig_name = sprintf('Gradient_Heatmap_MEDIAN_METHOD_v%d', round(cons_method_2_version_counter));

                                cons_method_2_version_counter = cons_method_2_version_counter+1;
                            end


                        % MIXED methods %
                        elseif user_input_method{1} == "mix mean" || user_input_method{1} == "mix median"

                            %determine bad channels
                            [channel_amp_data_Cutoff_logical, channel_grad_data_Cutoff_logical, low_sig_range_all_channels_val_logical] = ...
                            ast_remove_bad_channels_mixed_formula(filter_amp_data_Condition, filter_grad_data_Condition, chanAmpDevThreshold, chanGradDevThreshold, user_input_method{1});


                            if sum(low_sig_range_all_channels_val_logical) > 0
                               warndlg(sprintf("WARNING: You have %.1f channels identified with low signal (i.e. low signal existed in more than 10%% of your trials). Best to check yo data!", sum(low_sig_range_all_channels_val_logical)));
                               lowSigWarning = 'True';
                            end

                            if user_input_method{1} == "mix mean"
                                ast_channel_selection_method = "mean";
                                %collect text for display
                                display_text_channel_changed = sprintf('%sAmplitude deviation Cutoff: %.1f \nGradient deviation Cutoff: %.1f\nLow Signal Cutoff: %.1f\n\n', ...
                                                                          sprintf("%s\n%s", display_text_channel, display_text_channel_mixed_mean), chanAmpDevThreshold, chanGradDevThreshold, lowSigValue);

                                msgbox_name = 'Progress Report: MIXED MEAN METHOD';
                                amp_fig_name = sprintf('Amplitude_Heatmap_MIXED_MEAN_METHOD_v%d', round(mix_method_1_version_counter));
                                grad_fig_name = sprintf('Gradient_Heatmap_MIXED_MEAN_METHOD_v%d', round(mix_method_1_version_counter));

                                mix_method_1_version_counter = mix_method_1_version_counter+1;
                            elseif user_input_method{1} == "mix median"
                                ast_channel_selection_method = "median";
                                %collect text for display
                                display_text_channel_changed = sprintf('%sAmplitude deviation Cutoff: %.1f \nGradient deviation Cutoff: %.1f\nLow Signal Cutoff: %.1f\n\n', ...
                                                                          sprintf("%s\n%s", display_text_channel, display_text_channel_mixed_median), chanAmpDevThreshold, chanGradDevThreshold, lowSigValue);

                                msgbox_name = 'Progress Report: MIXED MEDIAN METHOD';
                                amp_fig_name = sprintf('Amplitude_Heatmap_MIXED_MEDIAN_METHOD_v%d', round(mix_method_2_version_counter));
                                grad_fig_name = sprintf('Gradient_Heatmap_MIXED_MEDIAN_METHOD_v%d', round(mix_method_2_version_counter));

                                mix_method_2_version_counter = mix_method_2_version_counter+1;
                            end

                        % VAR method %
                        elseif user_input_method{1} == "var"
                            ast_channel_selection_method = "var";

                            %determine bad channels
                            [channel_amp_data_Cutoff_logical, channel_grad_data_Cutoff_logical, low_sig_range_all_channels_val_logical] = ...
                            ast_remove_bad_channels_variability_formula(filter_amp_data_Condition, filter_grad_data_Condition, chanAmpDevThreshold, chanGradDevThreshold, lowSigValue);

                            if sum(low_sig_range_all_channels_val_logical) > 0
                               warndlg(sprintf("WARNING: You have %.1f channels identified with low signal (i.e. low signal existed in more than 10%% of your trials). Best to check yo data!", sum(low_sig_range_all_channels_val_logical)));
                               lowSigWarning = 'True';
                            end


                            %collect text for display
                            display_text_channel_changed = sprintf('%sAmplitude deviation Cutoff: %.1f \nGradient deviation Cutoff: %.1f\nLow Signal Cutoff: %.1f\n\n', ...
                                                                          sprintf("%s\n%s", display_text_channel, display_text_channel_variability), chanAmpDevThreshold, chanGradDevThreshold, lowSigValue);

                            msgbox_name = 'Progress Report: VARIABILITY METHOD';
                            amp_fig_name = sprintf('Amplitude_Heatmap_VARIABILITY_METHOD_v%d', round(var_method_version_counter));
                            grad_fig_name = sprintf('Gradient_Heatmap_VARIABILITY_METHOD_v%d', round(var_method_version_counter));
                            var_method_version_counter = var_method_version_counter+1;

                        end

                        %excute removal of bad channels
                        [bad_channels_to_be_removed, all_amp_data_bad_chnls_removed, all_grad_data_bad_chnls_removed] = ...
                        ast_remove_bad_channels_execute(all_amp_data, all_grad_data, channel_amp_data_Cutoff_logical, low_sig_range_all_channels_val_logical, ...
                        channel_grad_data_Cutoff_logical, channel_numbers);
                        
                    end
                    
                    %gather bad channels table for display %
                    display_bad_channel_table = ast_remove_bad_channels_display(channel_amp_data_Cutoff_logical, ...
                                                channel_grad_data_Cutoff_logical, low_sig_range_all_channels_val_logical, channel_labels);

                    %create figure for table %
                    display_bad_channel_table_fig = figure('Name', msgbox_name, 'NumberTitle','off', 'Position', [680 558 792 420]);

                    %create text info for table figure
                    display_bad_channel_table_text = annotation(display_bad_channel_table_fig, 'textbox', 'String', ...
                                                        display_text_channel_changed, 'Units', 'pixels', 'Position', [20 20 300 400]);
                    
                    %create table for table figure
                    display_bad_channel_table_item = uitable(display_bad_channel_table_fig, 'Data', ...
                                                    display_bad_channel_table, 'ColumnEditable', true, 'ColumnWidth', 'auto', ...
                                                    'Units', 'pixels', 'Position', ...
                                                    [(display_bad_channel_table_text.Position(4)+display_bad_channel_table_text.Position(1))+15 ...
                                                    display_bad_channel_table_text.Position(2) ...
                                                    display_bad_channel_table_text.Position(3)+30 ...
                                                    display_bad_channel_table_text.Position(4)]);


                    figure('Name',amp_fig_name,'NumberTitle','off', 'Position', [150 300 400 200]);
                    %[100 400 500 400]
                    subplot(3,1,1);
                    hMapAmpRawFixed = ast_display_heatmap(ast_condition_sort(all_amp_data, userConditionNum), heatmap_fixed_vals(1), heatmap_fixed_vals(2), ...
                        'Amplitude Heatmap Fixed', bad_channels_to_be_removed, 1, 0, ast_channel_selection_method, channel_labels);
                    subplot(3,1,2);
                    hMapAmpRawNormed = ast_display_heatmap(ast_condition_sort(all_amp_data, userConditionNum), amp_heatmap_max, amp_heatmap_min, ...
                        'Amplitude Heatmap Normed', bad_channels_to_be_removed, 1, 0, ast_channel_selection_method, channel_labels);
                    subplot(3,1,3);
                    hMapAmpBlockedNormed = ast_display_heatmap(ast_condition_sort(all_amp_data, userConditionNum), amp_heatmap_max, amp_heatmap_min, ...
                        'Amplitude Heatmap Normed', bad_channels_to_be_removed, 2, 0, ast_channel_selection_method, channel_labels);


                    figure('Name',grad_fig_name,'NumberTitle','off', 'Position', [200 300 400 200]);
                    %[1300 400 500 400]
                    subplot(3,1,1);
                    hMapGradRaw = ast_display_heatmap(ast_condition_sort(all_grad_data, userConditionNum), heatmap_fixed_vals(3), heatmap_fixed_vals(4), ...
                        'Gradient Heatmap Fixed', bad_channels_to_be_removed, 1, 0, ast_channel_selection_method, channel_labels);
                    subplot(3,1,2);
                    hMapGradRawNormed = ast_display_heatmap(ast_condition_sort(all_grad_data, userConditionNum), grad_heatmap_max, grad_heatmap_min, ...
                        'Gradient Heatmap Normed', bad_channels_to_be_removed, 1, 0, ast_channel_selection_method, channel_labels);
                    subplot(3,1,3);
                    hMapGradBlockedNormed = ast_display_heatmap(ast_condition_sort(all_grad_data, userConditionNum), grad_heatmap_max, grad_heatmap_min, ...
                        'Gradient Heatmap Normed', bad_channels_to_be_removed, 2, 0, ast_channel_selection_method, channel_labels);


                    user_input_bad_channel_method = inputdlg(sprintf('To accept bad channels and proceed to trial exclusions, enter (end).\nTo revise channel exclusions, enter (rev)'), ...
                                                    'Channel Advance', 1, {'end'}, diag_options);
                    
                end
                
                user_input_bad_channel_method = user_input_method{1};
                %close(ancestor(display_bad_channel_table_fig, 'figure'));
                
                
                
                
                % HALFWAY POINT %
                
                
                
                
                % Sort by an all condition, this time with the data that has bad
                % channels removed %
                filter_amp_data_Condition = ast_condition_sort(all_amp_data_bad_chnls_removed, userConditionNum);
                filter_grad_data_Condition = ast_condition_sort(all_grad_data_bad_chnls_removed, userConditionNum);

                % Get the max (across channels) max amplitude and max gradient for each
                % trial %
                max_amp_range_all_trials = max(filter_amp_data_Condition(:,3:end), [], 2);
                max_grad_range_all_trials = max(filter_grad_data_Condition(:,3:end), [], 2);

                % proceed to determine amplitude and gradient thresholds %
                display_text_trial = sprintf(['%s###   INFORMATION PROMPT   ###\nDecide what your amplitude and gradient cutoffs will be.\n'...
                    'Trials with low signal will automatically be removed regardless of trial exclusion method'], display_text_sub);
                waitfor(msgbox(sprintf("%s\n\n\nClick OK to proceed", display_text_trial),'TRIAL EXCLUSION THRESHOLDS', 'replace'));

                user_input_bad_trial_method = {''};
                while user_input_bad_trial_method{1} ~= "end"
                    user_input_method = inputdlg(sprintf('Which trial exclusion method would you like to use?\n\nFor AUTO, enter (auto).\nFor manual entry, enter (manual).\n'), ...
                        'TRIAL EXCLUSION METHOD', 1, {'auto'}, diag_options);
                    % force correct input %
                    while user_input_method{1} ~= "auto" && user_input_method{1} ~= "manual"
                        user_input_method = inputdlg(sprintf('A valid option was not selected.\nWhich trial exclusion method would you like to use?\n\nFor AUTO, enter (auto).\nFor manual entry, enter (manual).\n'), ...
                            'TRIAL EXCLUSION METHOD', 1, {'auto'}, diag_options);
                    end

                    if user_input_method{1} == "auto"
                        % calculate cutoffs based on user-defined MAD
                        trialHighCutoffMAD = inputdlg('Enter a new deviation cutoff: ', 'Amplitude & Gradient MAD', 1, {'3'}, diag_options);
                        trialHighCutoffMAD = str2double(trialHighCutoffMAD{1});
                        while isnan(trialHighCutoffMAD)
                            trialHighCutoffMAD = inputdlg('A valid value was not entered.\nEnter a new deviation cutoff: ', 'Amplitude & Gradient MAD', 1, {'3'}, diag_options);
                            trialHighCutoffMAD = str2double(trialHighCutoffMAD{1});
                        end
                        % Creaate a high statistical cutoff for trials %
                        trialAmpHighCutoff = median(max_amp_range_all_trials)+(trialHighCutoffMAD*mad(max_amp_range_all_trials,1));
                        trialGradHighCutoff = median(max_grad_range_all_trials)+(trialHighCutoffMAD*mad(max_grad_range_all_trials,1));

                        
                    elseif user_input_method{1} == "manual"
                        trialHighCutoff = inputdlg({'Enter an amplitude cutoff value: ', 'Enter a gradient cutoff value: '}, 'Amplitude & Gradient Cutoffs', 1, cellstr(string(heatmap_fixed_vals(1:2))), diag_options);
                        trialAmpHighCutoff = str2double(trialHighCutoff{1});
                        trialGradHighCutoff = str2double(trialHighCutoff{2});
                        while isnan(trialAmpHighCutoff) || isnan(trialGradHighCutoff)
                            trialHighCutoff = inputdlg({'A valid value was not entered.\nEnter an amplitude cutoff value: ', 'Enter a gradient cutoff value: '}, 'Amplitude & Gradient Cutoffs', 1, ...
                                cellstr(string(heatmap_fixed_vals(1:2))), diag_options);
                        trialAmpHighCutoff = str2double(trialHighCutoff{1});
                        trialGradHighCutoff = str2double(trialHighCutoff{2});
                        end

                        trialHighCutoffMAD = '-';
                        
                    end

                    amp_fig_name = 'Amplitude_Heatmap';
                    grad_fig_name = 'Gradient_Heatmap';
                    
                    display_text_trial_change = sprintf('%s\nMAD: %.1f\nLow Signal Cutoff: %.1f\nAmplitude Cutoff: %.1f\nGradient Cutoff: %.1f\n\n', display_text_trial, ...
                    trialHighCutoffMAD, lowSigValue, round(trialAmpHighCutoff), round(trialGradHighCutoff));
                
                
                    % filter data for trial trial counting by condition %
                    filtered_trial_times_data_removed = ast_distribution_filter(max_amp_range_all_trials, round(trialAmpHighCutoff), max_grad_range_all_trials, round(trialGradHighCutoff), ...
                        filter_amp_data_Condition, all_amp_data_bad_chnls_removed, lowSigValue);



                    % Display accepted trials per condition %
                    for j=1:size(allConditions,1)
                        label = allConditions{j,1};
                        num = allConditions{j,2};
                        allConditions{j,3} = sum(all_amp_data_bad_chnls_removed(:,1) == num);
                        allConditions{j,4} = sum(filtered_trial_times_data_removed(:,1) == num);
                    end
                    
                    %create figure for table %
                    display_bad_trial_table_fig = figure('Name', 'Progress Report: TRIAL EXCLUSION', 'NumberTitle','off', 'Position', [680 558 763 300]);

                    %create text info for table figure
                    display_bad_trial_table_text = annotation(display_bad_trial_table_fig, 'textbox', 'String', display_text_trial_change,...
                                                'Units', 'pixels', 'Position', [20 20 250 250]);
                    
                    %create table for table figure
                    display_bad_trial_table_item = uitable(display_bad_trial_table_fig, 'Data', ...
                                                    vertcat({'Condition_Label', 'Condition_Number', 'Total_Trials', 'Accepted_Trials'}, allConditions), 'ColumnEditable', true, 'ColumnWidth', {100 100 100 100},...
                                                    'Units', 'pixels', 'Position', ...
                                                    [(display_bad_trial_table_text.Position(4)+display_bad_trial_table_text.Position(1))+20 ...
                                                    display_bad_trial_table_text.Position(2) ...
                                                    display_bad_trial_table_text.Position(3)+200 ...
                                                    display_bad_trial_table_text.Position(4)]);

                    figure('Name',amp_fig_name,'NumberTitle','off', 'Position', [100 300 400 200]);
                    %[100 400 500 400]
                    subplot(3,1,1);
                    hMapAmpRaw = ast_display_heatmap(ast_condition_sort(all_amp_data, userConditionNum), heatmap_fixed_vals(1), heatmap_fixed_vals(2), ...
                        'Amplitude Heatmap Fixed', bad_channels_to_be_removed, 3, round(trialAmpHighCutoff), user_input_bad_channel_method, channel_labels);
                    subplot(3,1,2);
                    hMapAmpRawNormed = ast_display_heatmap(ast_condition_sort(all_amp_data, userConditionNum), amp_heatmap_max, amp_heatmap_min, ...
                        'Amplitude Heatmap Normed', bad_channels_to_be_removed, 3, round(trialAmpHighCutoff), user_input_bad_channel_method, channel_labels);
                    subplot(3,1,3);
                    hMapAmpBlockedNormed = ast_display_heatmap(ast_condition_sort(all_amp_data, userConditionNum), amp_heatmap_max, amp_heatmap_min, ...
                        'Amplitude Heatmap Normed', bad_channels_to_be_removed, 4, round(trialAmpHighCutoff), user_input_bad_channel_method, channel_labels);


                    figure('Name',grad_fig_name,'NumberTitle','off', 'Position', [150 300 400 200]);
                    %[1300 400 500 400]
                    subplot(3,1,1);
                    hMapGradRaw = ast_display_heatmap(ast_condition_sort(all_grad_data, userConditionNum), heatmap_fixed_vals(3), heatmap_fixed_vals(4), ...
                        'Gradient Heatmap Fixed', bad_channels_to_be_removed, 3, round(trialGradHighCutoff), user_input_bad_channel_method, channel_labels);
                    subplot(3,1,2);
                    hMapGradRawNormed = ast_display_heatmap(ast_condition_sort(all_grad_data, userConditionNum), grad_heatmap_max, grad_heatmap_min, ...
                        'Gradient Heatmap Normed', bad_channels_to_be_removed, 3, round(trialGradHighCutoff), user_input_bad_channel_method, channel_labels);
                    subplot(3,1,3);
                    hMapGradBlockedNormed = ast_display_heatmap(ast_condition_sort(all_grad_data, userConditionNum), grad_heatmap_max, grad_heatmap_min, ...
                        'Gradient Heatmap Normed', bad_channels_to_be_removed, 4, round(trialGradHighCutoff), user_input_bad_channel_method, channel_labels);


                    % Plot the average max amplitude and average max gradient for the specified
                    %condition
                    figure('Name','Distribution Plot','NumberTitle','off', 'Position', [200 300 400 200]);
                    %[700 250 500 400]
                    subplot(2,1,1);
                    histAmpDist = histogram(max_amp_range_all_trials,'BinWidth',25,'FaceColor','b');
                    lim = max(histAmpDist.Values)+1;
                    hold on
                    histAmpLimDist = histogram(repmat(trialAmpHighCutoff,lim,1),'FaceColor','k');
                    legend('Max Amp Range');
                    %pos1 = get(gcf,'Position'); % get position of Figure(1) 
                    %set(gcf,'Position', pos1 - [pos1(3)/2,0,0,0]) % Shift position of Figure(1)
                    datacursormode on
                    subplot(2,1,2);
                    histGradDist = histogram(max_grad_range_all_trials,'BinWidth',5,'FaceColor','r');
                    lim = max(histGradDist.Values)+1;
                    hold on
                    histGradLimDist = histogram(repmat(trialGradHighCutoff,lim,1),'FaceColor','k');
                    legend('Max Grad Range');
                    %%If they're on separate figures, use this to set the position
                    %set(gcf,'Position', get(gcf,'Position') + [0,0,150,0]); % When Figure(2) is not the same size as Figure(1)
                    %pos2 = get(gcf,'Position');  % get position of Figure(2) 
                    %set(gcf,'Position', pos2 + [pos1(3)/2,0,0,0]) % Shift position of Figure(2)
                    datacursormode on
                    
                    
                    user_input_bad_trial_method = inputdlg(sprintf('To accept trial thresholds, enter (end).\nTo revise trial thresholds, enter (rev)'), 'Trial Advance', 1, {'end'}, diag_options);
                    close(ancestor(display_bad_trial_table_fig, 'figure'));
                end
                
                user_input_bad_trial_method = user_input_method{1};
                user_input_cycle = inputdlg(sprintf('To accept Artifact Scan parameters, enter (end).\nTo restart, enter (res)'), 'Artifact Scan Complete', 1, {'end'}, diag_options);
            end
            
            % Process is complete, wait for user to request to proceed and store
            % data %
            waitfor(msgbox('Press OK to move on to the next PDG file.','Advance to Next File','replace'))
            
            bad_channels_to_be_removed = double(ismember(channel_numbers,bad_channels_to_be_removed));

            % Written to PDG file later in script %
%             bad_channels_to_be_removed_pdg = zeros(1,channel_numbers_orig_size);
%             bad_channels_to_be_removed_pdg(1,1:sensor_range(1)) = 0;
%             bad_channels_to_be_removed_pdg(1,sensor_range(1):sensor_range(2)) = bad_channels_to_be_removed;
%             bad_channels_to_be_removed_pdg(1,sensor_range(2)+1:channel_numbers_orig_size) = 0;
%             bad_channels_to_be_removed_pdg(bad_channels_to_be_removed_pdg==1) = 2;
%             bad_channels_to_be_removed_pdg = cellstr(num2str(bad_channels_to_be_removed_pdg, '%d\t'));
%             pdgFileContent{1}(ArtifactScanIndex+2) = bad_channels_to_be_removed_pdg;
            %channel_numbers_orig_size

            % Match bad channels with labels for .bad file %
            bad_channels_to_be_removed_labels = channel_labels(logical(bad_channels_to_be_removed), :);
            
            % Get BESA version %
            besaVersion = dir('C:\Users\Public\Documents\BESA');
            if size(besaVersion,1) > 3
                warndlg("WARNING: More than one version of BESA found?? Bad channels will be stored based on the latest convention and may result in errors.");
            end
            besaVersion = str2double(besaVersion(end).name(end-2));
            if besaVersion < 7
                if ~size(bad_channels_to_be_removed_labels) == 0
                    %cut out 'EG' in MEG labels
                    bad_channels_to_be_removed_labels = strcat('M',bad_channels_to_be_removed_labels(:,4:end));
                end
            end

            %%Create new data (amplitude, gradient, low signal, and bad_channels notes) for PDG
            ThreshIndex = find(strcmp(pdgFileContent{1,1},'[Thresholds]'));
            
            if strcmp(sensor_type,'GRADs')
                AmpRow = transpose(split(pdgFileContent{1}(ThreshIndex+5)));
                AmpRow{3} = num2str(round(trialAmpHighCutoff), '%.3f');
                AmpRow{2} = num2str(round(999999), '%.3f');
                pdgFileContent{1}(ThreshIndex+5) = cellstr(sprintf('%s\t', AmpRow{1,:}));
                GradRow = transpose(split(pdgFileContent{1}(ThreshIndex+7)));
                GradRow{3} = num2str(round(trialGradHighCutoff), '%.3f');
                GradRow{2} = num2str(round(999999), '%.3f');
                pdgFileContent{1}(ThreshIndex+7) = cellstr(sprintf('%s\t', GradRow{1,:}));
            elseif strcmp(sensor_type,'MAGs')
                AmpRow = transpose(split(pdgFileContent{1}(ThreshIndex+5)));
                AmpRow{3} = num2str(round(999999), '%.3f');
                AmpRow{2} = num2str(round(trialAmpHighCutoff), '%.3f');
                pdgFileContent{1}(ThreshIndex+5) = cellstr(sprintf('%s\t', AmpRow{1,:}));
                GradRow = transpose(split(pdgFileContent{1}(ThreshIndex+7)));
                GradRow{3} = num2str(round(999999), '%.3f');
                GradRow{2} = num2str(round(trialGradHighCutoff), '%.3f');
                pdgFileContent{1}(ThreshIndex+7) = cellstr(sprintf('%s\t', GradRow{1,:}));
            end
                
            LowSigRow = transpose(split(pdgFileContent{1}(ThreshIndex+6)));
            LowSigRow{2} = num2str(round(lowSigValue), '%.6f');
            LowSigRow{3} = num2str(round(lowSigValue), '%.6f');
            pdgFileContent{1}(ThreshIndex+6) = cellstr(sprintf('%s\t', LowSigRow{1,:}));

            %Create a 'v1' version of .bad and .PDG for backup if they don't already
            %exist
            
            if exist(fullfile(paradigmFileInfo(f).folder, sprintf("%s.PDG._v1", newFNameRoot{1})), 'file') == 0
                copyfile(fullfile(paradigmFileInfo(f).folder, paradigmFileInfo(f).name), fullfile(paradigmFileInfo(f).folder, sprintf("%s.PDG._v1", newFNameRoot{1})), 'f');
            end
            if exist(fullfile(paradigmFileInfo(f).folder, sprintf("%s.bad._v1", newFNameRoot{1})), 'file') == 0
                if exist(fullfile(paradigmFileInfo(f).folder, sprintf("%s.bad", newFNameRoot{1})),'file')
                    copyfile(fullfile(paradigmFileInfo(f).folder, sprintf("%s.bad", newFNameRoot{1})), fullfile(paradigmFileInfo(f).folder, sprintf("%s.bad._v1", newFNameRoot{1})), 'f');
                end
            end

            % Save data to paradigm file %
            newPDGFile = fopen(fullfile(paradigmFileInfo(f).folder, paradigmFileInfo(f).name), 'w+');
            % printing method currently only valid in MTLB >= 2016, alternative is
            % to loop? %
            fprintf(newPDGFile,"%s\n",string(pdgFileContent{:}));
            fclose(newPDGFile);
            
            blinkStatus = 'incomplete';
            cardiacStatus = 'incomplete';
            icaStatus = 'incomplete';
            % Determine if blink and cardiac was completed %
            if exist(fullfile(paradigmFileInfo(f).folder, sprintf("%s.atf", newFNameRoot{1})), 'file') ~= 0
                blinkCardiacFile = fopen(fullfile(paradigmFileInfo(f).folder, sprintf("%s.atf", newFNameRoot{1})), 'r');
                blinkCardiacFileContent = textscan(blinkCardiacFile,'%s','delimiter','\n');
                fclose(blinkCardiacFile);
                blinkIndex = find(strcmp(blinkCardiacFileContent{1,1},'BLINK'));
                cardiacIndex = find(strcmp(blinkCardiacFileContent{1,1},'EKG'));
                if sum(contains(blinkCardiacFileContent{1}, 'BLINK')) > 0
                    blinkStatus = 'complete';
                end
                if sum(contains(blinkCardiacFileContent{1}, 'EKG')) > 0
                    cardiacStatus = 'complete';
                    
                end
            end
            icaFile = dir(fullfile(allDirs{d}, '*.ica'));
            if length(icaFile) == 1
                icaStatus = 'complete';
            end
            

            % Save summary info to csv file %
            % setup log file column headers %
            logFile = {'parID' 'sensorType' 'blinkCompleted' 'cardiacCompleted' 'icaCompleted' 'lowSignalWarning' ...
                'badChannelAmpMADThreshold' 'badChannelGradMADThreshold' 'badChannelMethod' 'badChannelLabels' ...
                'trialMADThreshold' 'trialMethod' 'ampCutoff' 'gradCutoff'};
            % add initial content %
            logFile(size(logFile,1)+1,1:size(logFile,2)) = {subID 
                sensor_type
                blinkStatus
                cardiacStatus
                icaStatus
                lowSigWarning
                chanAmpDevThreshold
                chanGradDevThreshold
                user_input_bad_channel_method 
                sprintf("%s;",transpose(string(bad_channels_to_be_removed_labels))) 
                trialHighCutoffMAD 
                user_input_bad_trial_method 
                round(trialAmpHighCutoff) 
                round(trialGradHighCutoff)};
            % add condition labels to column headers %
            logFile(1,size(logFile,2)+1:size(logFile,2)+size(transpose(allConditions(:,1)),2)) = strcat(transpose(allConditions(:,1)), '_Total_Trials');
            % add condition trial counts under each condition %
            logFile(size(logFile,1),size(logFile,2)-size(transpose(allConditions(:,1)),2)+1:size(logFile,2)) = transpose(allConditions(:,3));
            % add condition labels to column headers %
            logFile(1,size(logFile,2)+1:size(logFile,2)+size(transpose(allConditions(:,1)),2)) = strcat(transpose(allConditions(:,1)), '_Accepted_Trials');
            % add condition trial counts under each condition %
            logFile(size(logFile,1),size(logFile,2)-size(transpose(allConditions(:,1)),2)+1:size(logFile,2)) = transpose(allConditions(:,4));
            
            % prepare the table and write to file %
            logFileTable = cell2table(logFile(2:end,:),'VariableNames',logFile(1,:));
            writetable(logFileTable,fullfile(paradigmFileInfo(f).folder, sprintf("%s_artifactScan_log.csv", newFNameRoot{1})))

            % Save data to bad channel file -
            % bad_channels_to_be_removed_labels %
            origBADFile = fopen(fullfile(paradigmFileInfo(f).folder, sprintf("%s.bad", newFNameRoot{1})), 'r');
            origBADFileContent = textscan(origBADFile,'%s','delimiter','\n');
            fclose(origBADFile);
            
            % shorten bad channel list based on bad channels that already
            % exist in .bad file to avoid duplicates %
            % If there are bad channels, add in those labels, otherwise no need to update .bad file %
            if size(bad_channels_to_be_removed_labels,1) ~= 0
                bad_channels_to_be_removed_labels = bad_channels_to_be_removed_labels(~ismember(bad_channels_to_be_removed_labels,origBADFileContent{1}),:);
                % update bad channel count from file header %
                origBADFileContentRow1 = split(origBADFileContent{1}(1));
                numBadChannels = round(str2double(origBADFileContentRow1{2})+size(bad_channels_to_be_removed_labels,1));
                origBADFileContent{1}(1) = cellstr(sprintf('%s %d', origBADFileContentRow1{1}, numBadChannels));
                
                % insert new information to bad file %
                origBADFileContent{1}(1+size(cellstr(bad_channels_to_be_removed_labels),1):end+size(cellstr(bad_channels_to_be_removed_labels),1),:) = origBADFileContent{1}(1:end,:);
                origBADFileContent{1}(2:2+size(cellstr(bad_channels_to_be_removed_labels),1)-1) = cellstr(bad_channels_to_be_removed_labels);
                
                % write out updated bad file %
                newBADFile = fopen(fullfile(paradigmFileInfo(f).folder, sprintf("%s.bad", newFNameRoot{1})), 'w+');
                fprintf(newBADFile,"%s\n",string(origBADFileContent{:}));
                fclose(newBADFile);
            end
            
        end
        % close all matlab figures and windows for the pdg file %
        close all hidden
        close all force
    end
end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
