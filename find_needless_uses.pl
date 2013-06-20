#!/usr/local/bin/perl
use strict;
use warnings;
use FindNeedlessUses;
use Cwd;

$\ = "\n";

my %param = (
	r => 0
);

foreach (0 .. $#ARGV) {
	if($ARGV[$_] =~ /-r/ || $ARGV[$_] =~ /--recursive/) {
		$param{r} = 1;
		$ARGV[$_] = undef;
	}
}

foreach (@ARGV) {
	next unless $_;
	if(-e $_ && -f $_) {
		work($_);
	} elsif ($param{r} && -d $_) {
		work_on_folder($_);
	}
}

sub work_on_folder {
	my $folder = shift;
	foreach (FindNeedlessUses::listFiles($folder, qr/.\.p[lm]$/, 1)) {
		if(-d $_) {
			work_on_folder($_);
		}
		if(-e $_) {
			work($_);
		}
	}
}

sub work {
	my $file = shift;
	print $file;

	foreach (FindNeedlessUses::getUnnecessaryUses(FindNeedlessUses::openFile($file))) {
		print "\t$_";
	}
	print "\n";
}
