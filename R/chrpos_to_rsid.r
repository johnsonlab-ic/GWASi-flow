chrpos_to_rsid=function(chromlocs,build=c("hg37","hg38")){

  original_names<-chromlocs
  chromlocs<-strsplit(chromlocs,":")
  chromlocs<-as.data.frame(do.call(rbind,chromlocs))
  chromlocs<-chromlocs[,1:2]
  colnames(chromlocs)<-c("Chr","Pos")

  if(length(grep("chr",chromlocs$Chr))!=0){
      chronly<-strsplit(as.character(chromlocs$Chr),"r")
      chronly<-as.data.frame(do.call(rbind,chronly))
      chromlocs$Chr<-chronly$V2
  }

  final<-data.frame(chrom=chromlocs[,1],position=chromlocs$Pos)
  final<-final[order(final$chrom),]
  final$paste<-paste0(final$chrom,":",final$position)

  grSNPS<-GenomicRanges::makeGRangesFromDataFrame(final,
  seqnames.field="chrom",
  start.field="position",
  end.field="position")

  if(build=="hg37"){
    snp<-SNPlocs.Hsapiens.dbSNP144.GRCh37::SNPlocs.Hsapiens.dbSNP144.GRCh37
  } else if(build=="hg38"){
    check_version=grep("155",system.file(package="SNPlocs.Hsapiens.dbSNP155.GRCh38"))
    if(length(check_version)==1){
      snp<-SNPlocs.Hsapiens.dbSNP155.GRCh38::SNPlocs.Hsapiens.dbSNP155.GRCh38
    }else{
      snp<-SNPlocs.Hsapiens.dbSNP151.GRCh38::SNPlocs.Hsapiens.dbSNP151.GRCh38
    }
  }

  rsids<-BSgenome::snpsByOverlaps(snp,grSNPS)
  rsids<-as.data.frame(rsids)
  rsids$paste<-paste0("chr",rsids$seqnames,":",rsids$pos)
  chromlocs$paste<-paste0("chr",chromlocs$Chr,":",chromlocs$Pos)

  chromlocs$original_names<-original_names
  chromlocs$rsid<-rsids$RefSNP_id[match(chromlocs$paste,rsids$paste)]
  chromlocs<-dplyr::mutate(chromlocs, rsid=dplyr::coalesce(rsid, original_names))

  return(chromlocs$rsid)
}