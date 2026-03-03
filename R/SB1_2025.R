library(ggplot2)

# Senate Bill 1 Homestead Deduction Calculator (numeric input version)
current<-function(gross_assessed_value) {
  standard_deduction=min(.6*gross_assessed_value,48000)
  supplemental_deduction=.275*gross_assessed_value+if(gross_assessed_value<=600000){(600000-gross_assessed_value)*.1}
  total_deduction=standard_deduction+supplemental_deduction
  Net_Taxable_AV=gross_assessed_value-total_deduction
}

# Example usage:
sb51(2027, 150000)

#Use the sb51 function for different a series of gross assessed values from 50000 to 10000000 in 2025
# Create a sequence of gross assessed values
gross_assessed_values <- seq(50000, 500000, by = 50000)
# Initialize an empty data frame to store results
results <- data.frame(
  Assessment_Year = integer(),
  Gross_AV = numeric(),
  Standard_Deduction = numeric(),
  Supplemental_Deduction = numeric(),
  Total_Deduction = numeric(),
  Net_Taxable_AV = numeric()
)
# Initialize an empty data frame to store results
old <- data.frame(
  Gross_AV = numeric(),
  Standard_Deduction = numeric(),
  Supplemental_Deduction = numeric(),
  Total_Deduction = numeric(),
  Net_Taxable_AV = numeric()
)
# Loop through each gross assessed value and calculate the deductions
for (value in gross_assessed_values) {
  result <- sb51(2025, value)
  results <- rbind(results, data.frame(
    Assessment_Year = result$Assessment_Year,
    Gross_AV = result$Gross_AV,
    Standard_Deduction = result$Standard_Deduction,
    Supplemental_Deduction = result$Supplemental_Deduction,
    Total_Deduction = result$Total_Deduction,
    Net_Taxable_AV = result$Net_Taxable_AV
  ))
}

# repeat for 2026, 2027, 2028, 2029, and 2030
for (year in 2026:2030) {
  for (value in gross_assessed_values) {
    result <- sb51(year, value)
    results <- rbind(results, data.frame(
      Assessment_Year = result$Assessment_Year,
      Gross_AV = result$Gross_AV,
      Standard_Deduction = result$Standard_Deduction,
      Supplemental_Deduction = result$Supplemental_Deduction,
      Total_Deduction = result$Total_Deduction,
      Net_Taxable_AV = result$Net_Taxable_AV
    ))
  }
}

for (value in gross_assessed_values) {
  old <- current(value)
  results <- rbind(results, data.frame(
    Assessment_Year = result$Assessment_Year,
    Gross_AV = result$Gross_AV,
    Standard_Deduction = result$Standard_Deduction,
    Supplemental_Deduction = result$Supplemental_Deduction,
    Total_Deduction = result$Total_Deduction,
    Net_Taxable_AV = result$Net_Taxable_AV
  ))
}


# Plot the results using ggplot2 with gross AV on the axis by Assessment Year
ggplot(results, aes(x = Gross_AV/10000, y = Net_Taxable_AV/Gross_AV, color = as.factor(Assessment_Year))) +
  geom_line() +
  labs(title = "Net Taxable Assessed Value by Assessment Year",
       x = "Gross Assessed Value (Tens. of Thousands, $)",
       y = "Net Taxable /Gross AV",
       color = "Assessment Year") +
  theme_minimal()


