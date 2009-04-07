package XrefParser::IlluminaWGParser;

use strict;

use base qw( XrefParser::BaseParser );


sub run {

  my $self = shift if (defined(caller(1)));

  my $source_id = shift;
  my $species_id = shift;
  my $files       = shift;
  my $release_file   = shift;
  my $verbose       = shift;

  my $file = @{$files}[0];


  my @xrefs;

  my $file_io = $self->get_filehandle($file);

  if ( !defined $file_io ) {
    print STDERR "Could not open $file\n";
    return 1;
  }

  my $read = 0;
  my $name_index;
  my $seq_index;
  my $defin_index;
  while ( $_ = $file_io->getline() ) {
    chomp;

    my $xref;

    # strip ^M at end of line
    $_ =~ s/\015//g;

    if(/^\[/){
      print $_."\n";
      if(/^\[Probes/){
	my $header = $file_io->getline();
	print $header."\n";
	$read =1;
	my @bits = split("\t", $header);
	my $index =0;
	foreach my $head (@bits){
	  if($head eq "Search_Key"){
	    $name_index = $index;
	  }
	  elsif($head eq "Probe_Sequence"){
	    $seq_index = $index;
	  }
	  elsif($head eq "Definition"){
	    $defin_index = $index;
	  }
	  $index++;
	}
	if(!defined($name_index) or !defined($seq_index) or !defined($defin_index)){
	  die "Could not find index for search_key->$name_index, seq->$seq_index, definition->$defin_index";
	}
      
	next;
      }
      else{
	$read = 0;
      }	
    }
    if($read){
#      print $_."\n";
      my @bits = split("\t", $_);
      my $sequence = $bits[$seq_index];

      my $description = $bits[$defin_index];
      my $illumina_id = $bits[$name_index];

      # build the xref object and store it
      $xref->{ACCESSION}     = $illumina_id;
      $xref->{LABEL}         = $illumina_id;
      $xref->{SEQUENCE}      = $sequence;
      $xref->{SOURCE_ID}     = $source_id;
      $xref->{SPECIES_ID}    = $species_id;
      $xref->{DESCRIPTION}   = $description;
      $xref->{SEQUENCE_TYPE} = 'dna';
      $xref->{STATUS}        = 'experimental';

      push @xrefs, $xref;
      
    }
  }

  $file_io->close();

  XrefParser::BaseParser->upload_xref_object_graphs(\@xrefs);


  print scalar(@xrefs) . " Illumina V2 xrefs succesfully parsed\n" if($verbose);

  return 0;
}

1;
