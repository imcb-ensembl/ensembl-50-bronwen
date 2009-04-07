package XrefParser::WormbaseDatabaseStableIDParser;

# Read gene and transcript stable IDs from a WormBase-imported database and create
# xrefs and direct xrefs for them.
# Note the only things that are actually WormBase specific here are the source names
# for the wormbase_gene and wormbase_transcript sources.

use strict;

use base qw( XrefParser::DatabaseParser );

sub run {
  my ($self, $dsn, $source_id, $species_id, $verbose) = @_;

  my $db = $self->connect($dsn); # source db (probably core)
  my $xref_db = $self->dbi();

  my $xref_sth = $xref_db->prepare( "INSERT INTO xref (accession,label,source_id,species_id) VALUES (?,?,?,?)" );
  my $direct_xref_sth = $xref_db->prepare( "INSERT INTO direct_xref (general_xref_id,ensembl_stable_id,type,linkage_xref) VALUES (?,?,?,?)" );

  # read stable IDs
  foreach my $type ('gene', 'transcript') {

    print "Building xrefs from $type stable IDs\n" if($verbose);

    my $wb_source_id = $self->get_source_id_for_source_name("wormbase_$type");

    my $sth = $db->prepare( "SELECT stable_id FROM ${type}_stable_id" );
    $sth->execute();

    while(my @row = $sth->fetchrow_array()) {

      my $id = $row[0];
      # add an xref & a direct xref
      $xref_sth->execute($id, $id, $wb_source_id, $species_id);
      my $xref_id = $xref_sth->{'mysql_insertid'};
      $direct_xref_sth->execute($xref_id, $id, $type, "Stable ID direct xref");

    } # while fetch stable ID

  } # foreach type
  return 0;
}

1;

