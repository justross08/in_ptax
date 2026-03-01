# Property Tax Bill Calculator pre-SB1 from TAXDATA

PTBill <- function(TAXDATA){
  TAXDATA$MaxTaxBill<-.01*(TAXDATA$AVLandCap1+TAXDATA$AVImprovCap1)+.02*(TAXDATA$AVNHRLandCap2+TAXDATA$AVNHRImprovCap2+TAXDATA$AVCommLandCap2+TAXDATA$AVCommImprovCap2+TAXDATA$AVLTCLandCap2+TAXDATA$AVLTCImprovCap2+TAXDATA$AVFarmCap2+TAXDATA$AVMobileLandCap2)+.03*(TAXDATA$AVLandCap3+TAXDATA$AVImprovCap3+TAXDATA$AVPPLocal+TAXDATA$AVPPState)
  TAXDATA$GrossTaxDue<-TAXDATA$NetAV*(TAXDATA$LocalTaxRate/100)-TAXDATA$LocalTaxRelief
  TAXDATA$NetTaxDue=TAXDATA$GrossTaxDue
  for (i in 1:nrow(TAXDATA)){
    if(TAXDATA$GrossTaxDue[i]>TAXDATA$MaxTaxBill[i]){TAXDATA$NetTaxDue[i]=TAXDATA$MaxTaxBill[i]}
  }
  TAXDATA$PTLoss<-TAXDATA$GrossTaxDue-TAXDATA$NetTaxDue
  tax_df<-TAXDATA[,c("ParcelNum","NetAV","LocalTaxRate","GrossTaxDue","NetTaxDue","PTLoss")]
}