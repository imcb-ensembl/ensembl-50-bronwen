# Parse UniProt (SwissProt & SPTrEMBL) files to create xrefs.
#
# Files actually contain both types of xref, distinguished by ID line;
#
# ID   CYC_PIG                 Reviewed;         104 AA.  Swissprot
# ID   Q3ASY8_CHLCH            Unreviewed;     36805 AA.  SPTrEMBL



package XrefParser::UniProtParser_descriptions_only;

use strict;
use POSIX qw(strftime);
use File::Basename;

use base qw( XrefParser::BaseParser );

# --------------------------------------------------------------------------------
# Parse command line and run if being run directly

if (!defined(caller())) {

  if (scalar(@ARGV) != 3) {
    print STDERR "\nUsage: UniProtParser.pm file.SPC <source_id> <species_id>\n\n";
    print STDERR scalar(@ARGV);
    exit(1);
  }

  run($ARGV[0], -1);

}

my $verbose;

# --------------------------------------------------------------------------------

sub run {

  my $self = shift if (defined(caller(1)));

  my $source_id    = shift;
  my $species_id   = shift;
  my $files         = shift;
  my $release_file = shift;
  $verbose      = shift;

  my $file = @{$files}[0];

  my $species_name;

  my ( $sp_source_id, $sptr_source_id, $sp_release, $sptr_release );

  if(!defined($species_id)){
    ($species_id, $species_name) = $self->get_species($file);
  }

  $sp_source_id =
    $self->get_source_id_for_source_name('Uniprot/SWISSPROT');
  $sptr_source_id =
    $self->get_source_id_for_source_name('Uniprot/SPTREMBL');

  print "SwissProt source id for $file: $sp_source_id\n" if($verbose);
  print "SpTREMBL source id for $file: $sptr_source_id\n" if($verbose);
 

  my @xrefs =
    $self->create_xrefs( $sp_source_id, $sptr_source_id, $species_id,
      $file );

  if ( !@xrefs ) {
      return 1;    # 1 error
  }

  # delete previous if running directly rather than via BaseParser
  if (!defined(caller(1))) {
    print "Deleting previous xrefs for these sources\n" if($verbose);
    $self->delete_by_source(\@xrefs);
  }

  # upload
  if(!defined($self->upload_xref_object_graphs(@xrefs))){
    return 1; 
  }

    if ( defined $release_file ) {
        # These two lines are duplicated from the create_xrefs() method
        # below...
        my $sp_pred_source_id =
          $self->get_source_id_for_source_name(
            'Uniprot/SWISSPROT_predicted');
        my $sptr_pred_source_id =
          $self->get_source_id_for_source_name(
            'Uniprot/SPTREMBL_predicted');

        # Parse Swiss-Prot and SpTrEMBL release info from
        # $release_file.
        my $release_io = $self->get_filehandle($release_file);
        while ( defined( my $line = $release_io->getline() ) ) {
            if ( $line =~ m#(UniProtKB/Swiss-Prot Release .*)# ) {
                $sp_release = $1;
                print "Swiss-Prot release is '$sp_release'\n" if($verbose);
            } elsif ( $line =~ m#(UniProtKB/TrEMBL Release .*)# ) {
                $sptr_release = $1;
                print "SpTrEMBL release is '$sptr_release'\n" if($verbose);
            }
        }
        $release_io->close();

        # Set releases
        $self->set_release( $sp_source_id,        $sp_release );
        $self->set_release( $sptr_source_id,      $sptr_release );
        $self->set_release( $sp_pred_source_id,   $sp_release );
        $self->set_release( $sptr_pred_source_id, $sptr_release );
    }


  return 0; # successfull
}

# --------------------------------------------------------------------------------
# Get species (id and name) from file
# For UniProt files the filename is the taxonomy ID

sub get_species {
  my $self = shift;
  my ($file) = @_;

  my ($taxonomy_id, $extension) = split(/\./, basename($file));

  my $sth = $self->dbi()->prepare("SELECT species_id,name FROM species WHERE taxonomy_id=?");
  $sth->execute($taxonomy_id);
  my ($species_id, $species_name);
  while(my @row = $sth->fetchrow_array()) {
    $species_id = $row[0];
    $species_name = $row[1];
  }
  $sth->finish;

  if (defined $species_name) {

    print "Taxonomy ID " . $taxonomy_id . " corresponds to species ID " . $species_id . " name " . $species_name . "\n" if($verbose);

  } else {

    print STDERR "Cannot find species corresponding to taxonomy ID " . $species_id . " - check species table\n";
    exit(1);

  }

  return ($species_id, $species_name);

}

# --------------------------------------------------------------------------------
# Parse file into array of xref objects

sub create_xrefs {
  my $self = shift;

  my ( $sp_source_id, $sptr_source_id, $species_id, $file ) = @_;

  my $num_sp = 0;
  my $num_sptr = 0;
  my $num_sp_pred = 0;
  my $num_sptr_pred = 0;


  # Get predicted equivalents of various sources used here
    my $sp_pred_source_id =
      $self->get_source_id_for_source_name(
        'Uniprot/SWISSPROT_predicted');
    my $sptr_pred_source_id =
      $self->get_source_id_for_source_name(
        'Uniprot/SPTREMBL_predicted');

  print "Predicted SwissProt source id for $file: $sp_pred_source_id\n" if($verbose);
  print "Predicted SpTREMBL source id for $file: $sptr_pred_source_id\n" if($verbose);

    my $uniprot_io = $self->get_filehandle($file);
    if ( !defined $uniprot_io ) { return undef }

  my @xrefs;

  local $/ = "//\n";

  # Create a hash of all valid taxon_ids for this species
  my %species2tax = $self->species_id2taxonomy();
  my @tax_ids = @{$species2tax{$species_id}};
  my %taxonomy2species_id = map{ $_=>$species_id } @tax_ids;

  while ( $_ = $uniprot_io->getline() ) {

    # if an OX line exists, only store the xref if the taxonomy ID that the OX
    # line refers to is in the species table
    # due to some records having more than one tax_id, we need to check them 
    # all and only proceed if one of them matches.
    #OX   NCBI_TaxID=158878, 158879;
    #OX   NCBI_TaxID=103690;

    my ($ox) = $_ =~ /OX\s+[a-zA-Z_]+=([0-9 ,]+);/;
    my @ox = ();
    my $found = 0;

    if ( defined $ox ) {
        @ox = split /\, /, $ox;

        # my %taxonomy2species_id = $self->taxonomy2species_id();

        foreach my $taxon_id_from_file (@ox) {
          if ( exists $taxonomy2species_id{$taxon_id_from_file} ){
            $found = 1;
          }
        }
    }

    next if (!$found); # no taxon_id's match, so skip to next record
    my $xref;

    # set accession (and synonyms if more than one)
    # AC line may have primary accession and possibly several ; separated synonyms
    # May also be more than one AC line
    my ($acc) = $_ =~ /(AC\s+.+)/s; # will match first AC line and everything else
    my @all_lines = split /\n/, $acc;

    # extract ^AC lines only & build list of accessions
    my @accessions;
    foreach my $line (@all_lines) {
      my ($accessions_only) = $line =~ /^AC\s+(.+)/;
      push(@accessions, (split /;\s*/, $accessions_only)) if ($accessions_only);
    }

    $xref->{ACCESSION} = $accessions[0];
    for (my $a=1; $a <= $#accessions; $a++) {
      push(@{$xref->{"SYNONYMS"} }, $accessions[$a]);
    }

    # Check for CC (caution) lines containing certain text
    # if this appears then set the source of this and and dependent xrefs to the predicted equivalents
    my $is_predicted = /CC.*EMBL\/GenBank\/DDBJ whole genome shotgun \(WGS\) entry/;

    my ($label, $sp_type) = $_ =~ /ID\s+(\w+)\s+(\w+)/;

    # SwissProt/SPTrEMBL are differentiated by having STANDARD/PRELIMINARY here
    if ($sp_type =~ /^Reviewed/i) {

      $xref->{SOURCE_ID} = $sp_source_id;
      if ($is_predicted) {
	$xref->{SOURCE_ID} = $sp_pred_source_id;
	$num_sp_pred++;
      } else {
	$xref->{SOURCE_ID} = $sp_source_id;
	$num_sp++;
      }
    } elsif ($sp_type =~ /Unreviewed/i) {

      if ($is_predicted) {
	$xref->{SOURCE_ID} = $sptr_pred_source_id;
	$num_sptr_pred++;
      } else {
	$xref->{SOURCE_ID} = $sptr_source_id;
	$num_sptr++;
      }

    } else {

      next; # ignore if it's neither one nor t'other

    }



    # some straightforward fields
    $xref->{LABEL} = $label;
    $xref->{SPECIES_ID} = $species_id;
    $xref->{SEQUENCE_TYPE} = 'peptide';
    $xref->{STATUS} = 'experimental';

    # May have multi-line descriptions
    my ($description_and_rest) = $_ =~ /(DE\s+.*)/s;
    @all_lines = split /\n/, $description_and_rest;

    # extract ^DE lines only & build cumulative description string
    my $description = " ";
    my $name        = "";
    my $flags       = " ";

    my $mode = "";
    foreach my $line (@all_lines) {

      next if(!($line =~ /^DE/));

      # Set up the mode first
      if($line =~ /^DE   RecName:/){
	if($mode eq "RecName"){
	  $description .= "; ";
	}	
        $mode = "RecName";
      }
      elsif($line =~ /^DE   SubName:/){
	if($mode eq "RecName"){
	  $description .= "; ";
	}	
        $mode = "RecName";
      }
      elsif($line =~ /^DE   AltName:/){
        $mode = "AltName";
      }
      elsif($line =~ /^DE   Contains:/){
	if($mode eq "Contains"){
	  $description .= "; ";
	}
        elsif($mode eq "Includes"){
          $description .= "][Contains ";
        }
	else{
          $description .= " [Contains ";
        }	
        $mode = "Contains";
        next;
      }
      elsif($line =~ /^DE   Includes:/){
	if($mode eq "Includes"){
	  $description .= "; ";
	}	
        elsif($mode eq "Contains"){
          $description .= "][Includess";
        }
	else{
          $description .= " [Includes ";
        }	
        $mode = "Includes";
        next;
      }
      elsif($line =~ /^DE   Flags: (.*);/){
        $flags .= "$1 ";
        next;
      }

      # now get the data
      if($line =~ /^DE   RecName: Full=(.*);/){
        $name .= $1;
      }
      elsif($line =~ /RecName: Full=(.*);/){
        $description .= $1;
      }
      elsif($line =~ /SubName: Full=(.*);/){
        $name .= $1;
      }
      elsif($line =~ /AltName: Full=(.*);/){
        $description .= "(".$1.")";        
      }
      elsif($line =~ /Short=(.*);/){
        $description .= "(".$1.")";        
      }
      elsif($line =~ /EC=(.*);/){
        $description .= "(EC ".$1.")";        
      }
      elsif($line =~ /Allergen=(.*);/){
        $description .= "(Allergen ".$1.")";        
      }
      elsif($line =~ /INN=(.*);/){
        $description .= "(".$1.")";        
      }
      elsif($line =~ /Biotech=(.*);/){
        $description .= "(".$1.")";        
      }
      elsif($line =~ /CD_antigen=(.*);/){
        $description .= "(".$1." antigen)";        
      }
      else{
         print STDERR "unable to process *$line* for $acc\n";
      }
    }
    if($mode eq "Contains" or $mode eq "Includes"){
      $description .= "]";
    }

    $description =~ s/^\s*//g;
    $description =~ s/\s*$//g;

    $xref->{DESCRIPTION} = $name.$flags.$description;


    push @xrefs, $xref;
    
  }

  $uniprot_io->close();

  print "Read $num_sp SwissProt xrefs and $num_sptr SPTrEMBL xrefs from $file\n" if($verbose);
  print "Found $num_sp_pred predicted SwissProt xrefs and $num_sptr_pred predicted SPTrEMBL xrefs\n" if (($num_sp_pred > 0 || $num_sptr_pred > 0) and $verbose);

  return \@xrefs;

  #TODO - currently include records from other species - filter on OX line??
}

1;
