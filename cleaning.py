import pandas as pd

# Set the path to your BehaviorSpace output file (CSV or Excel)
file_path = 'CombinedVersion1.0 - 512 size gridSearch-spreadsheet.csv'  # Change to the correct path for your file

# Read the data based on file type (CSV or Excel)
if file_path.endswith('.csv'):
    df = pd.read_csv(file_path)
elif file_path.endswith('.xlsx'):
    df = pd.read_excel(file_path)
else:
    print("Unsupported file format")
    exit()

# Display the data as a table
import ace_tools as tools; tools.display_dataframe_to_user(name="BehaviorSpace Results", dataframe=df)

# Optionally, you can print the first few rows of the dataframe to the console:
print(df.head())