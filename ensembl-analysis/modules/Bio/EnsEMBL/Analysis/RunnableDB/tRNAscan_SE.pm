# Ensembl module for Bio::EnsEMBL::Analysis::RunnableDB::tRNAscan_SE
#
# Copyright (c) 2004 Ensembl
#

=head1 NAME

Bio::EnsEMBL::Analysis::RunnableDB::tRNAscan_SE

=head1 SYNOPSIS

  my $runnable = Bio::EnsEMBL::Analysis::RunnableDB::tRNAscan_SE->
  new(
      -input_id => 'contig::AL805961.22.1.166258:1:166258:1',
      -db => $db,
      -analysis => $analysis,
     );
  $runnable->fetch_input;
  $runnable->run;
  $runnable->write_output;

=head1 DESCRIPTION

This module provides an interface between the ensembl database and
the Runnable tRNAscan_SE which wraps the program tRNAscan_SE

This module can fetch appropriate input from the database
pass it to the runnable then write the results back to the database
in the simple_feature table

=head1 CONTACT

Post questions to the Ensembl development list: ensembl-dev@ebi.ac.uk

=cut

package Bio::EnsEMBL::Analysis::RunnableDB::tRNAscan_SE;

use strict;
use warnings;

use Bio::EnsEMBL::Analysis::RunnableDB;
use Bio::EnsEMBL::Analysis::Runnable::tRNAscan_SE;

use vars qw(@ISA);

@ISA = qw(Bio::EnsEMBL::Analysis::RunnableDB);



=head2 fetch_input

  Arg [1]   : Bio::EnsEMBL::Analysis::RunnableDB::tRNAscan_SE
  Function  : fetch data out of database and create runnable
  Returntype: 1
  Exceptions: none
  Example   : 

=cut



sub fetch_input{
  my ($self) = @_;
  my $slice = $self->fetch_sequence;
  $self->query($slice);
  my %parameters;
  if($self->parameters_hash){
    %parameters = %{$self->parameters_hash};
  }
  my $runnable = Bio::EnsEMBL::Analysis::Runnable::tRNAscan_SE->new
    (
     -query => $self->query,
     -program => $self->analysis->program_file,
     -analysis => $self->analysis,
     %parameters,
    );
  $self->runnable($runnable);
  return 1;
}


=head2 get_adaptor

  Arg [1]   : Bio::EnsEMBL::Analysis::RunnableDB::tRNAscan_SE
  Function  : get simple_feature adaptor
  Returntype: Bio::EnsEMBL::DBSQL::SimpleFeatureAdaptor
  Exceptions: none
  Example   : 

=cut


sub get_adaptor{
  my ($self) = @_;
  return $self->db->get_SimpleFeatureAdaptor;
}

1;
