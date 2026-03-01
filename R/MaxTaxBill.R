# Maximum property tax bill under the propoerty tax caps.

MaxTaxBill <- function(TAXDATA){
  TAXDATA$MaxTaxBill<-.01*(TAXDATA$AVLandCap1+TAXDATA$AVImprovCap1)+.02*(TAXDATA$AVNHRLandCap2+TAXDATA$AVNHRImprovCap2+TAXDATA$AVCommLandCap2+TAXDATA$AVCommImprovCap2+TAXDATA$AVLTCLandCap2+TAXDATA$AVLTCImprovCap2+TAXDATA$AVFarmCap2+TAXDATA$AVMobileLandCap2)+.03*(TAXDATA$AVLandCap3+TAXDATA$AVImprovCap3+TAXDATA$AVPPLocal+TAXDATA$AVPPState)
  tax_df<-TAXDATA[,c("ParcelNum","MaxTaxBill")]
}