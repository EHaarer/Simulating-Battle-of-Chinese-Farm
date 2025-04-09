import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Step 1: Load the cleaned data
file_path = 'CombinedVersion1.0 - 512 size gridSearch-spreadsheet.csv'
data = pd.read_csv(file_path)

# Step 2: Basic data check
print("Data shape:", data.shape)
print("Data columns:", data.columns)
print("First few rows of the data:")
print(data.head())

# Step 3: Convert time column to datetime (if applicable) and set it as index
# data['Time'] = pd.to_datetime(data['Time'])
# data.set_index('Time', inplace=True)

# Step 4: Check for missing values
print("Missing data per column:")
print(data.isnull().sum())

# Step 5: Plot the time series data for different variables
plt.figure(figsize=(12, 6))
sns.lineplot(data=data[['Israeli_tanks', 'Egyptian_tanks', 'Israeli_infantry', 'Egyptian_infantry']])
plt.title('Time Series of Different Variables')
plt.xlabel('Time')
plt.ylabel('Values')
plt.legend(title='Variables')
plt.show()

# Step 6: Basic statistical summary for the variables
print("Statistical summary of the variables:")
print(data.describe())

# Step 7: Correlation matrix between variables
corr_matrix = data[['Israeli_tanks', 'Egyptian_tanks', 'Israeli_infantry', 'Egyptian_infantry']].corr()
sns.heatmap(corr_matrix, annot=True, cmap='coolwarm', fmt='.2f')
plt.title('Correlation Matrix of Variables')
plt.show()

# Step 8: Compare runs based on the parameters `e-epsilon`, `e-gamma`, and `e-alpha`
# Assuming these parameters are columns in the dataset
# If the parameters are repeated, group by them and analyze

# Example: Average values per run and parameter setting
grouped_data = data.groupby(['e-epsilon', 'e-gamma', 'e-alpha']).mean()
print(grouped_data)

# Plot comparison of runs with different parameters
plt.figure(figsize=(12, 6))
sns.boxplot(x='e-epsilon', y='Israeli_tanks', data=data)
plt.title('Comparison of Israeli Tanks based on e-epsilon Parameter')
plt.show()