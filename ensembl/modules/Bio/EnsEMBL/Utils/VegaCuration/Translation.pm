package Bio::EnsEMBL::Utils::VegaCuration::Translation;

=head1 NAME

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
use vars qw(@ISA);
use Data::Dumper;

use Bio::EnsEMBL::Utils::VegaCuration::Transcript;

@ISA = qw(Bio::EnsEMBL::Utils::VegaCuration::Transcript);

=head2 check_CDS_end_remarks

   Args       : B::E::Transcript
   Example    : my $results = $support->check_CDS_end_remarks($transcript)
   Description: identifies incorrect 'CDS end...' transcript remarks in a
                otter-derived Vega database
   Returntype : hashref

=cut

sub check_CDS_start_end_remarks {
	my $self = shift;
	my $trans = shift;

	# info for checking
	my @remarks = @{$trans->get_all_Attributes('remark')};
	my $coding_end   = $trans->cdna_coding_end;
	my $coding_start = $trans->cdna_coding_start;
	my $trans_end    = $trans->length;
	my $trans_seq    = $trans->seq->seq;
	my $stop_codon   = substr($trans_seq, $coding_end-3, 3);
	my $start_codon  = substr($trans_seq, $coding_start-1, 3);

	#hashref to return results
	my $results;

	#extra CDS end not found remarks
	if (grep {$_->value eq 'CDS end not found'} @remarks) {
		if (   ($coding_end != $trans_end) 
            && ( grep {$_ eq $stop_codon} qw(TGA TAA TAG) ) ) {
			$results->{'END_EXTRA'} = 1;
		}
	}

	#missing CDS end not found remark
	if ( $coding_end == $trans_end ) {
		if (! grep {$_->value eq 'CDS end not found'} @remarks) {
			if (grep {$_ eq $stop_codon} qw(TGA TAA TAG)) {
				$results->{'END_MISSING_2'} = 1;
			}
			else {
				$results->{'END_MISSING_1'} = $stop_codon;
			}
		}
	}


	#extra CDS start not found remark
	if (grep {$_->value eq 'CDS start not found'} @remarks) {
		if (   ($coding_start != 1) 
			&& ($start_codon eq 'ATG') ) {
			$results->{'START_EXTRA'} = 1;
		}
	}

	#missing CDS start not found remark
	if ( $coding_start == 1) {
		if ( ! grep {$_->value eq 'CDS start not found'} @remarks) {
			if ($start_codon eq 'ATG') {
				$results->{'START_MISSING_2'} = 1;
			} else {
				$results->{'START_MISSING_1'} = $start_codon;
			}
		}
	}

	return $results;
}

=head2 check_CDS_end_remarks_loutre

   Args       : B::E::Transcript
   Example    : my $results = $support->check_CDS_end_remarks($transcript)
   Description: identifies incorrect 'CDS end...' transcript attribs in a loutre
                of a loutre-derived Vega database.
   Returntype : hashref

=cut

sub check_CDS_start_end_remarks_loutre {
	my $self = shift;
	my $trans = shift;

	# info for checking
	my @stops = qw(TGA TAA TAG);
	my %attributes;
	foreach my $attribute (@{$trans->get_all_Attributes()}) {
		$attributes{$attribute->code} = $attribute;
	}
	my $coding_end   = $trans->cdna_coding_end;
	my $coding_start = $trans->cdna_coding_start;
	my $trans_end    = $trans->length;
	my $trans_seq    = $trans->seq->seq;
	my $stop_codon   = substr($trans_seq, $coding_end-3, 3);
	my $start_codon  = substr($trans_seq, $coding_start-1, 3);

	#hashref to return results
	my $results;

	#extra CDS end not found remarks
	if ( ($attributes{'cds_end_NF'}->value == 1)
			 && ($coding_end != $trans_end) 
				 && ( grep {$_ eq $stop_codon} @stops) ) {
		$results->{'END_EXTRA'} = 1;
	}
	#missing CDS end not found remark
	if ( $coding_end == $trans_end ) {
		if ($attributes{'cds_end_NF'}->value == 0 ) {
			if (grep {$_ eq $stop_codon} @stops) {
				$results->{'END_MISSING_2'} = 1;
			}
			else {
				$results->{'END_MISSING_1'} = $stop_codon;
			}
		}
	}
	#extra CDS start not found remark
	if ( ($attributes{'cds_start_NF'}->value == 1 )
			 && ($coding_start != 1)
				 && ($start_codon eq 'ATG') ) {
		$results->{'START_EXTRA'} = 1;
	}
	#missing CDS start not found remark
	if ( $coding_start == 1) {
		if ( $attributes{'cds_start_NF'}->value == 0 ) {
			if ($start_codon eq 'ATG') {
				$results->{'START_MISSING_2'} = 1;
			} else {
				$results->{'START_MISSING_1'} = $start_codon;
			}
		}
	}
	return $results;
}

=head2 get_havana_seleno_comments

   Args       : none
   Example    : my $results = $support->get_havana_seleno_comments
   Description: parses the HEREDOC containing Havana comments in this module
   Returntype : hashref

=cut

sub get_havana_seleno_comments {
	my $seen_translations;
	while (<DATA>) {
		next if /^\s+$/ or /#+/;
		my ($obj,$comment) = split /=/;
		$obj =~ s/^\s+|\s+$//g;
		$comment =~ s/^\s+|\s+$//g;
		$seen_translations->{$obj} = $comment;
	}
	return $seen_translations;
}

sub check_for_stops {
	my $support = shift;
	my ($gene,$seen_transcripts) = @_;
	my $scodon = 'TGA';

 TRANS:
	foreach my $trans (@{$gene->get_all_Transcripts}) {
		my $tsi = $trans->stable_id;
		my $tID = $trans->dbID;
		my $tname = $trans->get_all_Attributes('name')->[0]->value;
		$support->log_verbose("Studying transcript $tsi ($tname, $tID)\n",1);
		
		my $peptide;
		
		# go no further if the transcript doesn't translate or if there are no stops
		next TRANS unless ($peptide = $trans->translate);

		my $pseq = $peptide->seq;
		my $orig_seq = $pseq;
		
		# (translate method trims stops from sequence end)
		next TRANS unless ($pseq =~ /\*/);
		$support->log("Stops found in $tsi ($tname)\n",1);
		
		# find out where and how many stops there are
		my @found_stops;
		my $mrna   = $trans->translateable_seq;
		my $offset = 0;
		my $tstop;
		while ($pseq =~ /([^\*]+)\*(.*)/) {
			my $pseq1_f = $1;
			$pseq = $2;
			my $seq_flag = 0;
			$offset += length($pseq1_f) * 3;
			my $stop = substr($mrna, $offset, 3);
			my $aaoffset = int($offset / 3)+1;
			push(@found_stops, [ $stop, $aaoffset ]);
			$tstop .= "$aaoffset ";
			$offset += 3;
		}
		
		# are all stops TGA...?
		my $num_stops = scalar(@found_stops);
		my $num_tga = 0;
		my $positions;
		foreach my $stop (@found_stops) {
			$positions .= $stop->[0]."(".$stop->[1].") ";
			if ($stop->[0] eq $scodon) {
				$num_tga++;
			}
		}
		
		my $source = $gene->source;
		#...no - an internal stop codon error in the database...
		if ($num_tga < $num_stops) {
			if ($source eq 'havana') {
				$support->log_warning("INTERNAL STOPS HAVANA: Transcript $tsi ($tname) has non \'$scodon\' stop codons:\nSequence = $orig_seq\nStops at $positions\n\n");
			}
			else {
				$support->log_verbose("INTERNAL STOPS EXTERNAL: Transcript $tsi ($tname) has non \'$scodon\' stop codons:\nSequence = $orig_seq\nStops at $positions\n\n");
			}
			
		}
		#...yes - check remarks
		else {
			my $flag_remark  = 0; # 1 if word seleno has been used
			my $flag_remark2 = 0; # 1 if existing remark has correct numbering
			
			my $alabel       = 'Annotation_remark- selenocysteine ';
			my $alabel2      = 'selenocysteine ';
			
			my $annot_stops;
			my $remarks;
			
			#get both hidden_remarks and remarks
			foreach my $remark_type ('remark','hidden_remark') {
				foreach my $attrib ( @{$trans->get_all_Attributes($remark_type)}) {
					push @{$remarks->{$remark_type}}, $attrib->value;
				}
			}
			
			#parse remarks to check syntax for location of edits
			while (my ($attrib,$remarks)= each %$remarks) {
				foreach my $text (@{$remarks}) {					
					if ( ($attrib eq 'remark') && ($text=~/^$alabel(.*)/) ){
						$support->log_warning("seleno remark for $tsi stored as Annotation_remark not hidden remark\n");
						$annot_stops=$1;
					}
					elsif ($text =~ /^$alabel2(.*)/) {
						$annot_stops=$1;
					}
				}
			}
			
			#check the location of the annotated edits matches actual stops in the sequence
			my @annotated_stops;
			if ($annot_stops){
				my $i = 0;
				foreach my $offset (split(/\s+/, $annot_stops)) {
					# not a number - ignore
					if ($offset!~/^\d+$/){
					}
					#OK if it matches a known stop
					elsif ($found_stops[$i]->[1] == $offset) {
						push  @annotated_stops, $offset;
					}
					# catch old annotations where number was in DNA not peptide coordinates
					elsif (($found_stops[$i]->[1] * 3) == $offset) {
						$support->log_warning("DNA: Annotated stop for transcript tsi ($tname) is in DNA not peptide coordinates\n");
					}
					# catch old annotations where number off by one
					elsif (($found_stops[$i]->[1]) == $offset+1) {
						$support->log_warning("PEPTIDE: Annotated stop for transcript $tsi ($tname) is out by one\n");
					}
					else {
						$support->log_warning("Annotated stop for transcript $tsi ($tname) does not match a TGA codon\n");
						push  @annotated_stops, $offset;
				}						
					$i++;
				}
			}
			
			#check location of found stops matches annotated ones - any new ones are reported
			foreach my $stop ( @found_stops ) {
				my $pos = $stop->[1];
				my $seq = $stop->[0];
				unless ( grep { $pos == $_} @annotated_stops) {
					if ($seen_transcripts->{$tsi}) {
						$support->log_verbose("Transcript $tsi ($tname) has potential selenocysteines but has been discounted by annotators:\n\t".$seen_transcripts->{$tsi}."\n");
					}
					else {
						$support->log("POTENTIAL SELENO ($seq) in $tsi ($tname) found at $pos\n");
					}
				}
			}
		}
	}
}


#details of annotators comments
__DATA__

OTTHUMT00000144659 = FIXED- changed to transcript
OTTHUMT00000276377 = FIXED- changed to transcript
OTTHUMT00000257741 = FIXED- changed to nmd
OTTHUMT00000155694 = NOT_FIXED- should be nmd but external annotation but cannot be fixed
OTTHUMT00000155695 = NOT_FIXED- should be nmd but external annotation but cannot be fixed
OTTHUMT00000282573 = FIXED- changed to unprocessed pseudogene
OTTHUMT00000285227 = FIXED- changed start site
OTTHUMT00000151008 = FIXED- incorrect trimming of CDS, removed extra stop codon
OTTHUMT00000157999 = FIXED- changed incorrect stop
OTTHUMT00000150523 = FIXED- incorrect trimming of CDS
OTTHUMT00000150525 = FIXED- incorrect trimming of CDS
OTTHUMT00000150522 = FIXED- incorrect trimming of CDS
OTTHUMT00000150521 = FIXED- incorrect trimming of CDS
OTTHUMT00000246819 = FIXED- corrected frame
OTTHUMT00000314078 = FIXED- corrected frame
OTTHUMT00000080133 = FIXED- corrected frame
OTTHUMT00000286423 = FIXED- changed to transcript
OTTMUST00000055509 = FIXED- error
OTTMUST00000038729 = FIXED- corrected frame
OTTMUST00000021760 = FIXED- corrected frame
OTTMUST00000023057 = FIXED- corrected frame
OTTMUST00000015207 = FIXED- corrected frame
OTTMUST00000056646 = FIXED- error
OTTMUST00000059686 = FIXED- corrected frame
OTTMUST00000013426 = FIXED- corrected frame
OTTMUST00000044412 = FIXED- error
