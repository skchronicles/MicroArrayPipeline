#' 6) ssGSEA function
#'
#' @export
#' @param deg_normAnnot Differentially expressed genes object from deg function
#' @param species Species of organism (human or mouse)
#' @param geneSet Choice of MSigDB gene set
#' @param workspace Working directory
#' @param projectId A unique identifier for the project
#' @param configuration_path Path to configuration files
#' @return List containing ssGSEA initial results and differentially expressed ssGSEA pathways
#' @examples
#' ssGSEA_results = ssgseaPathways(diff_expr_genes,'human','C2: Curated Gene Sets','/Users/name/folderName','NCI_Project_1','/Users/name/config')
#' @note Human Gene Set Choices: "H: Hallmark Gene Sets", "C1: Positional Gene Sets", "C2: Curated Gene Sets", "C3: Motif Gene Sets", "C4: Computational Gene Sets","C5: GO gene sets", "C6: Oncogenic Signatures", "C7: Immunologic Signatures"
#' @note Mouse Gene Set Choices: "H: Hallmark Gene Sets", "C2: Curated Gene Sets", "C3: Motif Gene Sets", "C4: Computational Gene Sets", "C5: GO gene sets", "C6: Oncogenic Signatures", "C7: Immunologic Signatures"
#' @references MSigDB: http://software.broadinstitute.org/gsea/msigdb/index.jsp.  Also see GSEABase, GSVA and pheatmap packages.
#' @references Mouse gene sets adapted from http://bioinf.wehi.edu.au/software/MSigDB/

ssgseaPathways = function(deg_normAnnot, species, geneSet,workspace,projectId,configuration_path){
  library(GSEABase)
  library(GSVA)
  library(pheatmap)
  
  ssgseaPathways_ERR = file(paste0(workspace,'/ssgseaPathways.err'),open='wt')
  sink(ssgseaPathways_ERR,type='message',append=TRUE)
  
  normAnnot = deg_normAnnot$norm_plots_annotated
  ssgs = normAnnot[normAnnot$SYMBOL!='NA',]
  #if human or mouse, prepare data for gsva
  if (tolower(species)=='human') {
    ssgs = subset(ssgs, select=-c(ACCNUM,DESC,Row.names,ENTREZ))
    ssgs = aggregate(.~SYMBOL,data=ssgs,mean)                               #aggregate duplicate probes by mean
    rownames(ssgs) = ssgs$SYMBOL
    ssgs = subset(ssgs, select=-c(SYMBOL))
    ssgs = as.matrix(ssgs)
    getSet = switch(geneSet, "H: Hallmark Gene Sets"="h.all.v6.2.symbols.gmt", "C1: Positional Gene Sets"="c1.all.v6.2.symbols.gmt", "C2: Curated Gene Sets"="c2.all.v6.2.symbols.gmt",
                    "C3: Motif Gene Sets"="c3.all.v6.2.symbols.gmt", "C4: Computational Gene Sets"="c4.all.v6.2.symbols.gmt","C5: GO gene sets"="c5.all.v6.2.symbols.gmt",
                    "C6: Oncogenic Signatures"="c6.all.v6.2.symbols.gmt", "C7: Immunologic Signatures"="c7.all.v6.2.symbols.gmt")
  } else {
    ssgs = subset(ssgs, select=-c(ACCNUM,DESC,Row.names,SYMBOL))
    ssgs = aggregate(.~ENTREZ,data=ssgs,mean)                               #aggregate duplicate probes by mean
    rownames(ssgs) = ssgs$ENTREZ
    ssgs = subset(ssgs, select=-c(ENTREZ))
    ssgs = as.matrix(ssgs)
    getSet = switch(geneSet, "Co-expression"="MousePath_Co-expression_entrez.gmt", "Gene Ontology"="MousePath_GO_entrez.gmt", "Curated Pathway"="MousePath_Pathway_entrez.gmt", "Metabolic"="MousePath_Metabolic_entrez.gmt",
                    "TF targets"="MousePath_TF_entrez.gmt", "miRNA targets"="MousePath_miRNA_entrez.gmt", "Location"="MousePath_Location_entrez.gmt")
  }
  getSet = paste0(configuration_path,'/',getSet)
  gset = getGmt(getSet)
  ssgsResults = gsva(ssgs, gset, method='ssgsea')                           #run ssGSEA
  y<-paste("_",projectId, sep="")                                           #write out results
  tSS = tempfile(pattern = "ssGSEA_enrichmentScores_", tmpdir =workspace, fileext = paste0(y,'.txt'))
  write.table(ssgsResults,file=tSS,sep="\t",col.names=NA)
  myfactor <- factor(deg_normAnnot$pheno$groups)
  design1 <- model.matrix(~0+myfactor)
  colnames(design1) <- levels(myfactor)
  fit1 = lmFit(ssgsResults,design1)                                                                                                      #DE analysis of ssGSEA enrichment scores
  cons = names(deg_normAnnot$listDEGs)
  contrast.matrix = makeContrasts(contrasts=cons,levels=design1)
  fit2 = contrasts.fit(fit1,contrast.matrix)
  ebayes.fit2 = eBayes(fit2)
  DEss=vector("list",length(deg_normAnnot$listDEGs))
  for (i in 1:length(deg_normAnnot$listDEGs))
  {
    all.pathways = topTable(ebayes.fit2, coef=i, number=nrow(ebayes.fit2))                                                               #Determine DE pathways
    all.pathways = all.pathways[order(abs(all.pathways$P.Value)),]
    colnames(all.pathways)[2] = 'Avg.Enrichment.Score'
    write.table(all.pathways,file=paste0(workspace,'/',projectId,"_",cons[i],"_ssGSEA_pathways.txt"),sep="\t",row.names=T,col.names=NA)
    DEss[[i]] = all.pathways
  }
  names(DEss)=cons
  for (i in 1:length(DEss)){                                                                                                             #Heatmap
    sampleColumns = c(which(deg_normAnnot$pheno$groups==gsub("-.*$","",cons[i])),which(deg_normAnnot$pheno$groups==gsub("^.*-","",cons[i])))   #Subset columns (samples)
    DEss_sig = DEss[[i]][DEss[[i]]$P.Value<0.05,]
    paths = ssgsResults[rownames(ssgsResults) %in% rownames(DEss_sig)[1:50],]                                                           #Subset rows (pathways)
    paths = paths[,sampleColumns]
    matCol = data.frame(group=deg_normAnnot$pheno$groups[sampleColumns])
    rownames(matCol) = rownames(deg_normAnnot$pheno)[sampleColumns]
    matColors = list(group = unique(deg_normAnnot$pheno$colors[sampleColumns]))
    names(matColors$group) = unique(deg_normAnnot$pheno$groups[sampleColumns])
    paths = t(scale(t(paths)))
    saveImageFileName<-paste0(workspace,'/ssgseaHeatmap',i,'.jpg',sep="")
    
    colNames = rownames(matCol)
    parsedNames = vector("list",length(colNames))
    for (i in 1:length(colNames)) {
      temp = substring(colNames[i], seq(1, nchar(colNames[i])-1, nchar(colNames[i])/2), seq(nchar(colNames[i])/2, nchar(colNames[i]), nchar(colNames[i])-nchar(colNames[i])/2))
      temp = paste(temp, collapse = '\n')
      parsedNames[[i]] = temp
    }
    
    pheatmap(paths,annotation_col=matCol,annotation_colors=matColors,drop_levels=TRUE,fontsize=7, main='Enrichment Scores for Top 50 Differentially Expressed ssGSEA Pathways (p-value<0.05)\n(Row Z-Scores)',filename=saveImageFileName,width=12,height = 12,labels_col = parsedNames)
  }
  print("+++ssGSEA+++")
  return(list(ssgsResults=ssgsResults, DEss=DEss))
  sink(type='message')
}


