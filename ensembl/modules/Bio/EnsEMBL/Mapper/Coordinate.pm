
#
# Ensembl module for Bio::EnsEMBL::MapperCoordinate
#
# Written by Ewan Birney <birney@ebi.ac.uk>
#
# Copyright GRL and EBI
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Mapper::Coordinate

=head1 SYNOPSIS

=head1 DESCRIPTION

Representation of a mapped region in a sequence; returned from
Mapper.pm when the target region maps on to valid sequence.

=head1 CONTACT

This module is part of the Ensembl project http://www.ensembl.org

Post general queries to B<ensembl-dev@ebi.ac.uk>

=head1 METHODS

=cut

package Bio::EnsEMBL::Mapper::Coordinate;

use strict;

=head2 new

  Arg [1]     char|int id of object in mapped region
  Arg [2]     int start of region   
  Arg [3]     int end of region
  Arg [4]     int strand if region
  Arg [5]     Bio::EnsEMBL::CoordSystem  coordsytem of the region
  Function    creates a new Coordinate object
  Returntype  Bio::EnsEMBL::Mapper::Coordinate
  Exceptions  none
  Status      Stable

=cut

sub new {
  my ( $proto, $id, $start, $end, $strand, $coord_system ) = @_;

  my $class = ref($proto) || $proto;

  return
    bless( { 'id'           => $id,
             'start'        => $start,
             'end'          => $end,
             'strand'       => $strand,
             'coord_system' => $coord_system
           },
           $class );
}


=head2 start

  Arg  1      int $start
              start coordinate of object in mapped region
  Function    getter/setter method
  Returntype  int
  Exceptions  none
  Caller      Bio::EnsEMBL::Mapper::Coordinate
  Status      Stable

=cut

sub start {
  my ( $self, $value ) = @_;

  if ( defined($value) ) {
    $self->{'start'} = $value;
  }

  return $self->{'start'};
}


=head2 end

  Arg  1      int $end
              end coordinate of object in mapped region
  Function    getter/setter method
  Returntype  int
  Exceptions  none
  Caller      Bio::EnsEMBL::Mapper::Coordinate
  Status      Stable

=cut

sub end {
  my ( $self, $value ) = @_;

  if ( defined($value) ) {
    $self->{'end'} = $value;
  }

  return $self->{'end'};
}

=head2 strand

  Arg  1      int $strand
              strand of object in mapped region
  Function    getter/setter method
  Returntype  int
  Exceptions  none
  Caller      Bio::EnsEMBL::Mapper::Coordinate
  Status      Stable

=cut

sub strand {
  my ( $self, $value ) = @_;

  if ( defined($value) ) {
    $self->{'strand'} = $value;
  }

  return $self->{'strand'};
}

=head2 id

  Arg  1      char|int $id
              id of object in mapped region
	      e.g. seq_region_id / seq_region_name
  Function    getter/setter method
  Returntype  char|int
  Exceptions  none
  Caller      Bio::EnsEMBL::Mapper::Coordinate
  Status      Stable

=cut

sub id {
  my ( $self, $value ) = @_;

  if ( defined($value) ) {
    $self->{'id'} = $value;
  }

  return $self->{'id'};
}

=head2 coord_system

  Arg  1      Bio::EnsEMBL::CoordSystem
  Function    getter/setter method
  Returntype  Bio::EnsEMBL::CoordSystem
  Exceptions  none
  Caller      Bio::EnsEMBL::Mapper::Coordinate
  Status      Stable

=cut

sub coord_system {
  my ( $self, $value ) = @_;

  if ( defined($value) ) {
    $self->{'coord_system'} = $value;
  }

  return $self->{'coord_system'};
}

=head2 length

  Function    getter method
  Returntype  int
  Exceptions  none
  Caller      ?
  Status      Stable

=cut

sub length {
  my ($self) = @_;

  return $self->{'end'} - $self->{'start'} + 1;
}

1;
