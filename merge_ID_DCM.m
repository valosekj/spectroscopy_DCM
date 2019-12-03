%
% Script for simplifying conversion xls (csv) table between spectroscopy
% (MRA) and diffusion (MRB) subjects ID
% Original table is not suitable for scripting

% Jan Valošek, 02-12-2019
% fMRI lab Olomouc

% USAGE:
%   - set path to input file, script fetch this file as cell and perform
%   simplifying and save it into new xls file. Output file contains 3
%   columns - MRA ID, MRB ID, patient ID


clc; clear all; close all

folder_path = '/home/valosek/Dropbox/Valosek_paper/DCM_shared_folder/Spektroskopie/';

% Path to csv file
path_table = [folder_path 'DCM_PRO_CEITEC_RC.csv'];

% Fetch csv table as cell
table_data = readcell(path_table);

%% Replace missing cells by NaN (regexp command cannot work with missing cells)
% Loop through individual lines
for line = 2:length(table_data)     % (first line is header)
   
    % Replace missing cells by NaN (regexp command cannot work with missing cells)
    if ismissing(table_data{line,4}) == 1
        table_data{line,4} = 'NaN';
    end
    
    if ismissing(table_data{line,5}) == 1
        table_data{line,5} = 'NaN';
    end
    
end

%% Create and fetch new table with subID for both MRA and MRB
% Loop through individual lines
for line = 2:length(table_data)     % (first line is header)
    
    % Replace empty array [] by zero (&& operator cannot work with [])
    % MRA - Spectroscopy
    MRA = regexp(table_data{line,4},'[0-9]{4}[A]');
    if isempty(MRA) == 1
        MRA = 0;
    end
    
    % MRB - dMRI
    MRB = regexp(table_data{line,5},'[0-9]{4}[B]');
    if isempty(MRB) == 1
        MRB = 0;
    end
        
    % Compare if given line contains subID for both MRA and MRB
    % Both MRA and MRB contain subID
    if (MRA == 1) && (MRB == 1)
        
        table_new{line-1,1} = table_data{line,4};   % MRA
        table_new{line-1,2} = table_data{line,5};   % MRB
        table_new{line-1,3} = table_data{line,1};   % ID
    
    % Only MRA containts subID
    elseif (MRA == 1) && (MRB == 0)
        
        table_new{line-1,1} = table_data{line,4};   % MRA
        table_new{line-1,3} = table_data{line,1};   % ID
        
        ID = table_data{line,1};
        
        for line2 = 2:length(table_data)     % (first line is header) 
            
            MRBB = regexp(table_data{line2,5},'[0-9]{4}[B]');   
            if isempty(MRBB) == 1
                MRBB = 0;
            end
            
           % Compare IDs and if MRB column contains subID 
           if (strcmp(ID,table_data{line2,1}) == 1) && (MRBB == 1)
               table_new{line-1,2} = table_data{line2,5};   % MRB
           end
        end
        
    % Only MRB containts subID
    elseif (MRA == 0) && (MRB == 1)
        
        table_new{line-1,2} = table_data{line,5};   % MRB
        table_new{line-1,3} = table_data{line,1};   % ID
        
        ID = table_data{line,1};
        
        for line3 = 2:length(table_data)     % (first line is header) 
                        
            MRAA = regexp(table_data{line3,4},'[0-9]{4}[A]');
            if isempty(MRAA) == 1
                MRAA = 0;
            end
            
           % Compare IDs and if MRA column contains subID 
           if (strcmp(ID,table_data{line3,1}) == 1) && (MRAA == 1)
               table_new{line-1,1} = table_data{line3,4};   % MRA
           end
        end
                
     end
    
end


%% Replace missing cells by NaN in new table
for line = 1:length(table_new)     % (first line is header)
   
    if isempty(table_new{line,1}) == 1
        table_new{line,1} = 'NaN';
    end
    
    if isempty(table_new{line,2}) == 1
        table_new{line,2} = 'NaN';
    end

end

%% Let every ID only one time in final table
% get only unique value
[C,ia,ic] = unique(table_new(:,1))

% Create table only with uniq values
for index = 1:length(ia)
   
    table_new_unique(index,1) = table_new(ia(index),1);
    table_new_unique(index,2) = table_new(ia(index),2);
    table_new_unique{index,3} = table_new(ia(index),3);

end

%% Write final table to .xls file

file = [folder_path 'DCM_PRO_CEITEC_RC_paired.xls'];

writetable(cell2table(table_new_unique),file,'WriteVariableNames',false);    % Write table_for_fill to .xls file (cell has to be converted to table)


