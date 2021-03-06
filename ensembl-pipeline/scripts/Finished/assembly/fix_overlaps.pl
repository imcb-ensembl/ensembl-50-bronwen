#!/software/bin/perl

=head1 NAME

fix_overlaps.pl - remove overlapping mappings between two closely related
assemblies

=head1 SYNOPSIS

fix_overlaps.pl [arguments]

Required arguments:

  --dbname, db_name=NAME              database name NAME
  --host, --dbhost, --db_host=HOST    database host HOST
  --port, --dbport, --db_port=PORT    database port PORT
  --user, --dbuser, --db_user=USER    database username USER
  --pass, --dbpass, --db_pass=PASS    database passwort PASS
  --assembly=ASSEMBLY                 assembly version ASSEMBLY
  --altassembly=ASSEMBLY              alternative assembly version ASSEMBLY

Optional arguments:

  --chromosomes, --chr=LIST           only process LIST chromosomes
  --altchromosomes, --altchr=LIST     supply alternative chromosome names (the two lists must agree)

  --conffile, --conf=FILE             read parameters from FILE
                                      (default: conf/Conversion.ini)

  --logfile, --log=FILE               log to FILE (default: *STDOUT)
  --logpath=PATH                      write logfile to PATH (default: .)
  --logappend, --log_append           append to logfile (default: truncate)

  -v, --verbose=0|1                   verbose logging (default: false)
  -i, --interactive=0|1               run script interactively (default: true)
  -n, --dry_run, --dry=0|1            don't write results to database
  -h, --help, -?                      print help (this message)

=head1 DESCRIPTION

This script removes overlapping mappings that were generated by the code in
align_nonident_regions.pl. Mappings are trimmed so that no overlaps are present
in the assembly table, because such overlaps may break the AssemblyMapper when
projecting between the two assemblies.

It also merges adjacent assembly segments which can result from alternating
alignments from clone identity and blastz alignment.

=head1 RELATED FILES

The whole process of creating a whole genome alignment between two assemblies
is done by a series of scripts. Please see

  ensembl/misc-scripts/assembly/README

for a high-level description of this process, and POD in the individual scripts
for the details.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Patrick Meidl <meidl@ebi.ac.uk>, Ensembl core API team

modified by Mustapha Larbaoui <ml6@sanger.ac.uk>

=head1 CONTACT

Please post comments/questions to Anacode
<anacode-people@sanger.ac.uk>

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);
BEGIN {
    $SERVERROOT = "$Bin/../../../..";
    unshift(@INC, "$Bin");
    unshift(@INC, "$SERVERROOT/ensembl/modules");
	unshift(@INC, "$SERVERROOT/bioperl-0.7.2");
    unshift(@INC, "$SERVERROOT/bioperl-1.2.3-patched");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
	'assembly=s',         'altassembly=s',
	'chromosomes|chr=s@', 'altchromosomes|altchr=s@',
);
$support->allowed_params( $support->get_common_params, 'assembly',
	'altassembly', 'chromosomes', 'altchromosomes', );

if ( $support->param('help') or $support->error ) {
	warn $support->error if $support->error;
	pod2usage(1);
}

$support->param('verbose', 1);
$support->param('interactive', 0);

$support->comma_to_list( 'chromosomes', 'altchromosomes' );


# get log filehandle and print heading and parameters to logfile
$support->init_log;

$support->check_required_params( 'assembly', 'altassembly' );

# database connection
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;

my $assembly    = $support->param('assembly');
my $altassembly = $support->param('altassembly');

my $select = qq(
  SELECT a.*
  FROM assembly a, seq_region sr1, seq_region sr2,
       coord_system cs1, coord_system cs2
  WHERE a.asm_seq_region_id = sr1.seq_region_id
  AND a.cmp_seq_region_id = sr2.seq_region_id
  AND sr1.coord_system_id = cs1.coord_system_id
  AND sr2.coord_system_id = cs2.coord_system_id
  AND cs1.name = 'chromosome'
  AND cs2.name = 'chromosome'
  AND cs1.version = '$assembly'
  AND cs2.version = '$altassembly'
  AND sr1.name = ?
  AND sr2.name = ?
  ORDER BY a.asm_start
);

my $sth_select = $dbh->prepare($select);

my $sql_insert = qq(INSERT INTO assembly VALUES (?, ?, ?, ?, ?, ?, ?));
my $sth_insert = $dbh->prepare($sql_insert);

my $fmt1 = "%10s %10s %10s %10s %3s\n";

$support->log_stamped("Looping over chromosomes...\n");

my @R_chr_list = $support->param('chromosomes');
die "Reference chromosome list must be defined!" unless scalar(@R_chr_list);

my @A_chr_list = $support->param('altchromosomes');
if ( scalar(@R_chr_list) != scalar(@A_chr_list) ) {
	die "Chromosome lists do not match by length";
}

for my $i ( 0 .. scalar(@R_chr_list) - 1 ) {
	my $R_chr = $R_chr_list[$i];
	my $A_chr = $A_chr_list[$i];
	my @rows  = ();

	$support->log_stamped( "Chromosome $R_chr/$A_chr ...\n", 1 );

	$sth_select->execute( $R_chr, $A_chr );

	# do an initial fetch
	my $last = $sth_select->fetchrow_hashref;

	# skip seq_regions for which we don't have data
	unless ($last) {
		$support->log( "No $R_chr/$A_chr mappings found. Skipping.\n", 1 );
		next;
	}

	push @rows, $last;

	my $i = 0;
	my $j = 0;
	my $k = 0;

	while ( $last and ( my $r = $sth_select->fetchrow_hashref ) ) {

		# merge adjacent assembly segments (these can result from alternating
		# alignments from clone identity and blastz alignment)
		if (    $last->{'asm_end'} == ( $r->{'asm_start'} - 1 )
			and $last->{'cmp_end'} == ( $r->{'cmp_start'} - 1 )
			and $last->{'ori'}  == $r->{'ori'} )
		{

			$j++;

			# debug warnings
			$support->log_verbose(
				'merging - last:   '
				  . sprintf( $fmt1,
					map { $last->{$_} }
					  qw(asm_start asm_end cmp_start cmp_end ori) ),
				1
			);
			$support->log_verbose(
				'this: '
				  . sprintf( $fmt1,
					map { $r->{$_} }
					  qw(asm_start asm_end cmp_start cmp_end ori) ),
				1
			);

			# remove last row
			pop(@rows);

			# merge segments and add new row
			$last->{'asm_end'} = $r->{'asm_end'};
			$last->{'cmp_end'} = $r->{'cmp_end'};
			push @rows, $last;

			next;
		}

	  # bridge small gaps (again, these can result from alternating alignments
	  # from clone identity and blastz alignment). A maximum gap size of 10bp is
	  # allowed
		my $asm_gap = $r->{'asm_start'} - $last->{'asm_end'} - 1;
		my $cmp_gap = $r->{'cmp_start'} - $last->{'cmp_end'} - 1;

		if ( $asm_gap == $cmp_gap and $asm_gap <= 10 and $asm_gap > 0 ) {

			$k++;

			# debug warnings
			$support->log_verbose(
				'bridging - last: '
				  . sprintf( $fmt1,
					map { $last->{$_} }
					  qw(asm_start asm_end cmp_start cmp_end ori) ),
				1
			);
			$support->log_verbose(
				'this:            '
				  . sprintf( $fmt1,
					map { $r->{$_} }
					  qw(asm_start asm_end cmp_start cmp_end ori) ),
				1
			);

			# remove last row
			pop(@rows);

			# merge segments and add new row
			$last->{'asm_end'} = $r->{'asm_end'};
			$last->{'cmp_end'} = $r->{'cmp_end'};
			push @rows, $last;

			next;
		}

		# look for overlaps with last segment
		if ( $last->{'asm_end'} >= $r->{'asm_start'} ) {

			$i++;

			# debug warnings
			$support->log_verbose(
				'last:   '
				  . sprintf( $fmt1,
					map { $last->{$_} }
					  qw(asm_start asm_end cmp_start cmp_end ori) ),
				1
			);
			$support->log_verbose(
				'before: '
				  . sprintf( $fmt1,
					map { $r->{$_} }
					  qw(asm_start asm_end cmp_start cmp_end ori) ),
				1
			);

			# skip if this segment ends before the last one
			if ( $r->{'asm_end'} <= $last->{'asm_end'} ) {
				$support->log_verbose( "skipped\n\n", 1 );
				next;
			}

			my $overlap = $last->{'asm_end'} - $r->{'asm_start'} + 1;

			$r->{'asm_start'} += $overlap;

			if ( $r->{'ori'} == -1 ) {
				$r->{'cmp_end'} -= $overlap;
			}
			else {
				$r->{'cmp_start'} += $overlap;
			}

			$support->log_verbose(
				'after:  '
				  . sprintf( $fmt1,
					map { $r->{$_} }
					  qw(asm_start asm_end cmp_start cmp_end ori) )
				  . "\n",
				1
			);
		}

		push @rows, $r;
		$last = $r;
	}

	$support->log( "$R_chr/$A_chr: Fixed $i mappings.\n",  1 );
	$support->log( "$R_chr/$A_chr: Merged $j mappings.\n", 1 );
	$support->log( "$R_chr/$A_chr: Bridged $k gaps.\n",    1 );

	# fix the assembly table
	if ( $support->param('dry_run') ) {
		$support->log("\nNothing else to do for a dry run.\n");
	}
	else {

		# delete all current mappings from the db and insert the corrected ones
		my $c = $dbh->do(
			qq(
    DELETE a
    FROM assembly a, seq_region sr1, seq_region sr2,
         coord_system cs1, coord_system cs2
    WHERE a.asm_seq_region_id = sr1.seq_region_id
    AND a.cmp_seq_region_id = sr2.seq_region_id
    AND sr1.coord_system_id = cs1.coord_system_id
    AND sr2.coord_system_id = cs2.coord_system_id
    AND cs1.name = 'chromosome'
    AND cs2.name = 'chromosome'
    AND cs1.version = '$assembly'
    AND cs2.version = '$altassembly'
    AND sr1.name = '$R_chr'
  	AND sr2.name = '$A_chr' )
		);
		$support->log(
			"\n$R_chr/$A_chr: Deleted $c entries from the assembly table.\n");

		# now insert the fixed entries
		foreach my $r (@rows) {
			$sth_insert->execute(
				map { $r->{$_} }
				  qw(asm_seq_region_id cmp_seq_region_id
				  asm_start asm_end cmp_start cmp_end ori)
			);
		}

		$support->log( "$R_chr/$A_chr: Added "
			  . scalar(@rows)
			  . " fixed entries to the assembly table.\n" );
	}
}

$sth_select->finish;
$sth_insert->finish;

# finish logfile
$support->finish_log;

