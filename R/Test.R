library(readxl)
Path<-"C:\\Users\\justross\\Dropbox\\PTCAPS\\data"
cPath<-"C:\\Users\\justross\\Dropbox\\PTCAPS\\code"
## Load Helper Functions
source(paste(cPath,"\\read_adjust.R",sep=""))
source(paste(cPath,"\\read_taxdata.R",sep=""))
source(paste(cPath,"\\PTBill.R",sep=""))
source(paste(cPath,"\\MaxTaxBill.R",sep=""))
source(paste(cPath,"\\sb1_supp.R",sep=""))
source(paste(cPath,"\\budget_tax_rates.R",sep=""))
source(paste(cPath,"\\district_tax_rates.R",sep=""))
source(paste(cPath,"\\district_rates.R",sep=""))
source(paste(cPath,"\\netav_taxbill.R",sep=""))
source(paste(cPath,"\\fiscal_analysis.R",sep=""))


#Code List for AdjstCode for type and amount of deduction, credit, or exemption
AdjustCodes<-read_excel(paste(Path,"\\AdjustCodes.xlsx",sep=""),sheet="Sheet1")

# Cumulative Capital Dev Funds with Fixed Tax Rates
FRF<-read_excel(paste(Path,"\\Fixed_Rate_Cap_Funds.xlsx",sep=""),sheet="Sheet1")

# Funds exempt from Property Tax Caps
CapExempt<-read_excel(paste(Path,"\\CapExemptFunds.xlsx",sep=""),sheet="Sheet1")

# Import Aggregate Budget Levy Data by Fund
BUDGETDATA<-read_excel(paste(Path,"\\2025_Certifed_Budget_Levy_CNAV_Rate_by_Fund.xlsx",sep=""),sheet="Sheet5")
BUDGETDATA.Adams<-BUDGETDATA[which(BUDGETDATA$County=="01"),]

# Import Tax District to Unit Fund Tax Rates for Cross Walk
xwalk<-read_excel(paste(Path,"\\2025_Certifed_Tax_Rates_by_District_Unit.xlsx",sep=""),sheet="Sheet1")
xwalk.Adams<-xwalk[which(xwalk$CNTY_CD=="01"),]

# Find the relevant tax rates.
BUDGETRATES<-budget_tax_rates(BUDGETDATA,FRF,CapExempt)
DISTRICTRATES_f<-district_tax_rates(xwalk,FRF,CapExempt)
DISTRICTRATES<-district_rates(DISTRICTRATES_f)



# Import Taxpayer Adjustments (if Testing, just use Adams County)
taxpayer_adjsts<-read_adjust(paste(Path,"\\ADJMENTS_Adams_01_2024p2025.txt",sep=""))

# Import Taxpayer Data (if Testing, just use Adams County)
#taxpayer_bills<-read_taxdata(paste(Path,"\\TAXDATA_ALLCOUNTIES_2024p2025.txt",sep=""))
taxpayer_bills<-read_taxdata(paste(Path,"\\TAXDATA_Adams_01_2024p2025.txt",sep=""))


# Caluclate Maximum Property Tax Bill allowed under the caps
maxbill<-MaxTaxBill(taxpayer_bills)

# Call SB1 Function to change adjustments to reflect new exemptions
New_adjst<-sb1_supp(2030,taxpayer_bills,taxpayer_adjsts)

# Call the netav_taxbill function to calculate NetAV for each taxpayer
New_taxpayer_av<-netav_taxbill(taxpayer_bills,New_adjst)


#######################################
#FISCAL ANALYSIS BLOCK
county=1
a_year=2030
taxpayer_bills<-read_taxdata(paste(Path,"\\TAXDATA_Adams_01_2024p2025.txt",sep=""))
taxpayer_adjsts<-read_adjust(paste(Path,"\\ADJMENTS_Adams_01_2024p2025.txt",sep=""))
New_adjst<-sb1_supp(a_year,taxpayer_bills,taxpayer_adjsts)
BUDGETDATA<-read_excel(paste(Path,"\\2025_Certifed_Budget_Levy_CNAV_Rate_by_Fund.xlsx",sep=""),sheet="Sheet5")
xwalk<-read_excel(paste(Path,"\\2025_Certifed_Tax_Rates_by_District_Unit.xlsx",sep=""),sheet="Sheet1")
FRF<-read_excel(paste(Path,"\\Fixed_Rate_Cap_Funds.xlsx",sep=""),sheet="Sheet1")
CapExempt<-read_excel(paste(Path,"\\CapExemptFunds.xlsx",sep=""),sheet="Sheet1")

results<-fiscal_analysis(county,a_year,taxpayer_bills, New_adjst, BUDGETDATA, xwalk,FRF, CapExempt)
BUDGETDATA_out<- results$out.BUDGETDATA

#######################################



# Calculate the sum of TotalAdjustAmount in New_adjusts where where AdjstCode is either 3 or 64
print(sum(New_adjst$TotalAdjustAmount[New_adjst$AdjstCode %in% c(3,64)])-sum(taxpayer_adjsts$TotalAdjustAmount[New_adjst$AdjstCode %in% c(3,64)]))

print(sum(New_adjst$TotalAdjustAmount[New_adjst$AdjstCode %in% c(80,81)])-sum(taxpayer_adjsts$TotalAdjustAmount[New_adjst$AdjstCode %in% c(80,81)]))

