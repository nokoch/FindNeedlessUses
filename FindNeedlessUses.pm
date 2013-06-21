package FindNeedlessUses;

=head
This module attempts to find all "use'd" Perl-Scripts, which are loaded, but not really required for the script to work.
Often people forget removing old use's when they comment out source-code, and so the use's stay there, like, practically forever.
They can use quite a lot of RAM and time, which is really not neccessary. 

This was developed in an environment, where PPI was not available, so I had to write it all by myself.

It doesn't work with XS-Scripts, so you have to add the module-name in perl-syntax ("Data::Dumper" instead of "Data/Dumper.pm")
in the __DATA__-block. It will be automatically parsed at startup-time. 
Also: This module just gives hints. Don't take them dead-serious, just see them as a possibly helpful clue.

This module is Copyright (c) 2012-2013 Norman Koch. Germany.
All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl 5.10.0 README file.

This Software is free Open Source software. IT COMES WITHOUT WARRANTY OF ANY KIND.
=cut

use strict;
use warnings;

sub _fill_internal_data ();
sub _skip_to_whitespace_reverse (\$$);
sub _skip_whitespace (\$$;$);
our $arrow_pseudo_delimiter = qr/[\W\s]/;
our $not_valid_varname      = qr/[^A-Za-z0-9_:\$]/;
our @perl_pragmas           = ();
our %xs_exports             = ();
_fill_internal_data;

sub _skip_whitespace (\$$;$) {
	my ($i, $array, $real_line) = @_;
	my $old_i = $$i;
	my $last  = ((scalar @{$array}) - 1);

	while ($array->[$$i] =~ /\s/) {

		if (ref $real_line && $array->[$$i] =~ /\r|\n/) {
			$$real_line = $$real_line + 1;
		}

		$$i = $$i + 1;
		if ($$i > $last) {
			$$i = $old_i;
			return;
		}

	} ## end while ($array->[$$i] =~ /\s/)

} ## end sub _skip_whitespace (\$$;$)

sub openFile {
	my $file = shift || '';
	return undef unless defined $file;
	return undef if $file =~ /^\s*$/;
	$file = createModuleName($file) unless -e $file;

	if (defined $file && -e $file && $file !~ /^\s*$/) {
		my $code = do {local $/; local @ARGV = $file; <>};
		return $code;
	} else {
		return '';
	}

} ## end sub openFile

sub _skip_to_whitespace_reverse (\$$) {
	my ($i, $array) = @_;
	my $old_i = $$i;
	do {
		$$i = $$i - 1;

		if ($$i > 0) {
			$$i = $old_i;
			return;
		}

	} while ($array->[$$i] !~ /\s/);

} ## end sub _skip_to_whitespace_reverse (\$$)

sub stripComments {
	my $code = shift;
	return unless $code;
	$code =~ s/(?:^|\n|\r)__(?:DATA|END)__.*//sg;                                   # Remove __DATA__ and __END__
	$code =~ s#(?:\R|^)(?:=.+?)\R=cut(?:\R|$)#"\n"x((${^MATCH}=~tr{\n|\r}{}))#segp; # Remove POD-Comments
	my @splitted          = split('', $code);
	my $i                 = 0;
	my $is_q_function     = 0;
	my $q_delimiter       = '';
	my $q_delimiter_begin = '';
	my $s_counter         = 0;
	my $is_comment        = 0;
	my $regex_started     = 0;
	my $is_regex          = 0;
	my $ignore_arrow      = 0;
	my $eol_next_line     = 0;
	my $is_eol            = 0;
	my $eol_delimiter     = '';
	my $add_string        = '';

	while ($i <= $#splitted) {
		if ($is_comment == 0 && $is_q_function == 0) {
			($is_q_function, $i, $regex_started, $q_delimiter, $s_counter, $add_string, $q_delimiter_begin, $is_regex, $ignore_arrow, $is_eol, $eol_next_line, $eol_delimiter) =
			  _isQFunction($i, $regex_started, $s_counter, \@splitted, $ignore_arrow, $is_eol, $eol_delimiter, $eol_next_line);
		}

		if ($splitted[$i] eq "\n" || $splitted[$i] eq "\r") {
			$is_comment = 0;

			if ($eol_next_line == 1) {
				$is_q_function = 1;
				$eol_next_line = 0;
			}

		} ## end if ($splitted[$i] eq "\n" || $splitted...)

		if (!$is_q_function && $splitted[$i] eq '#' && $splitted[$i - 1] ne '$') {
			$is_comment = 1;
		} ## end if (!$is_q_function && $splitted...)

		if ($is_comment) {
			$splitted[$i] = '';
		}

		if ($is_q_function) {
			$i++ if ($splitted[$i] eq '\\');

			if ($is_eol && !$eol_next_line) {
				if (($i + length($eol_delimiter) <= $#splitted) && join('', map {$splitted[$_]} $i - 1 .. $i + length($eol_delimiter)) =~ /\R\Q$eol_delimiter\E\R/) {
					$is_q_function = 0;
					$is_eol        = 0;
					$eol_next_line = 0;
				}

			} else {

				if (($#splitted >= $i + 1) && $splitted[$i + 1] eq $q_delimiter) {
					if ($s_counter) { # regex mit s ist erst beendet, wenn 3 ungequotete delimiter gefunden wurden

						if ($s_counter == 2) {
							$s_counter         = 0;
							$is_q_function     = 0;
							$is_regex          = 0;
							$q_delimiter       = '';
							$q_delimiter_begin = '';
							$i++;
						} else {
							$s_counter++;
						}

					} else {
						$is_q_function     = 0;
						$is_regex          = 0;
						$q_delimiter       = '';
						$q_delimiter_begin = '';
						$i++;
					} ## end else [ if ($s_counter) ]

				} elsif (::re::is_regexp($q_delimiter) && $splitted[$i + 1] =~ $q_delimiter) {
					$is_q_function     = 0;
					$q_delimiter       = '';
					$q_delimiter_begin = '';
					$add_string        = '';
					$i++;
				} ## end elsif (::re::is_regexp($q_delimiter...))

			} ## end else [ if ($is_eol && !$eol_next_line) ]

		} ## end if ($is_q_function)

		_afterMatching(\$regex_started, \$i, $is_q_function, \@splitted);
	} ## end while ($i <= $#splitted)

	my $str = join('', @splitted);
	return $str;
} ## end sub stripComments


## Trys to find needed uses, not in use right now
sub findNeededUses {
	my $code = shift;
	my $revert = shift || 0;
	return () unless $code;
	$code = stripComments($code);
	my @ownPackages                   = getPackages($code);
	my @uses                          = ();
	my @splitted                      = split('', $code);
	my $i                             = 0;
	my $is_q_function                 = 0;
	my $q_delimiter                   = ''; 
	my $q_delimiter_begin             = '';
	my $s_counter                     = 0; 
	my $is_comment                    = 0;
	my $regex_started                 = 0;
	my $is_regex                      = 0;
	my $ignore_arrow                  = 0;
	my $eol_next_line                 = 0;
	my $is_eol                        = 0;
	my $eol_delimiter                 = '';
	my %ignore                        = ();
	my $add_string                    = '';
	my @really_used                   = FindNeedlessUses::getUses($code, 1, 0);
	my @really_used_included_packages = ();

	foreach (@really_used) {
		push @really_used_included_packages, getPackages(openFile(createModuleName($_)));
	}

	push @really_used, (@ownPackages, @really_used_included_packages);
	my $exit_regex = qr/\s|;|\{|\(|\[|'|"/;
	my $ignore_regex = join('|', map {quotemeta $_} @perl_pragmas);
	$ignore_regex = qr/$ignore_regex/;

	while ($i <= $#splitted) {

		if (!$is_comment && !$is_q_function && !$regex_started) {
			($is_q_function, $i, $regex_started, $q_delimiter, $s_counter, $add_string, $q_delimiter_begin, $is_regex, $ignore_arrow, $is_eol, $eol_next_line, $eol_delimiter) =
			  _isQFunction($i, $regex_started, $s_counter, \@splitted, $ignore_arrow, $is_eol, $eol_delimiter, $eol_next_line);
		}

		if ($splitted[$i] eq "\n" || $splitted[$i] eq "\r") {
			$is_comment = 0;

			if ($eol_next_line == 1) {
				$is_q_function = 1;
				$eol_next_line = 0;
			}

		} ## end if ($splitted[$i] eq "\n" || $splitted...)

		if (!$is_q_function && $splitted[$i - 1] ne '$') {
			if ($splitted[$i] eq '#') {
				$is_comment = 1;
			} ## end if ($splitted[$i] eq '#')

		} ## end if (!$is_q_function && $splitted...)

		if (!$is_comment && !$is_q_function) {
			my $before = $i;
			my $after  = $i;

			if ($splitted[$i] eq '-' && $splitted[$i + 1] eq '>') { # my $dbh = DBI::connect
				while ($splitted[$i] !~ /\s/) {
					$i--;
				}

				## Prev.: (_ _: cursor):
				## DBI->_connect()
				## Now:
				## _ _DBI->connect();
				$i++;
				$after = $i;

				if (exists $ignore{$i}) {
					while (exists $ignore{$i} || $splitted[$i] !~ /\w/) {
						$i++;
						last if $i >= $#splitted;
					}

				} ## end if (exists $ignore{$i})

				if ($splitted[$i - 1] =~ /\s|\w|&/ && $splitted[$i] =~ /\s|\w/) {
					my $use_name = '';

					while ($splitted[$i] !~ $exit_regex) {
						$use_name .= $splitted[$i];
						$i++;
					}

					$use_name = _stringToModName($use_name);
					if ($use_name && !grep($_ eq $use_name, @really_used)) {
						$use_name = _stringToModName($use_name);

						if ($use_name && !grep($_ eq $use_name, @really_used)) {
							push @uses, $use_name;
						}

					} ## end if ($use_name && !grep($_ eq $use_name...))

					$i += ($before - $after);
				} ## end if ($splitted[$i - 1] =~ /\s|\w|&/...)

			} elsif ($splitted[$i] eq ':' && $splitted[$i + 1] eq ':') {
				while ($splitted[$i] !~ /\s/) {
					$i--;
				}

				$i++;
				$after = $i;

				if (exists $ignore{$i}) {
					while (exists $ignore{$i} || $splitted[$i] !~ /\w/) {
						$i++;
					}

				} ## end if (exists $ignore{$i})

				if (join('', map {$splitted[$_]} $i - 8 .. $i - 2) ne 'package' && $splitted[$i - 1] =~ /\s|\w|&/ && $splitted[$i] =~ /\s|\w/) {
					my $use_name = '';

					while ($splitted[$i] !~ $exit_regex) { # bis zum naechsten whitespace oder ; gehen
						$use_name .= $splitted[$i];
						$i++;
					}

					$use_name =~ s/->.*$//g;

					if ($use_name && !grep($_ eq $use_name, @really_used)) {
						$use_name = _stringToModName($use_name);

						if ($use_name && !grep($_ eq $use_name, @really_used)) {
							push @uses, $use_name;
						}

					} ## end if ($use_name && !grep($_ eq $use_name...))

					$i += ($before - $after);
				} ## end if (join('', map {$splitted[$_]}...))

			} elsif (
				($#splitted >= $i + 3) && join(
					'',
					map {
						$splitted[$_]
					} $i .. $i + 3
				) =~ /new\s/
			  ) { # my $hashlist = new Module;

				$i += 3;
				$i++;
				_skip_whitespace $i, \@splitted;

				if ($splitted[$i] !~ /\$|\@|\%/) {
					my $use_name = '';

					while ($splitted[$i] !~ $exit_regex) { # bis zum naechsten whitespace oder ; gehen
						$use_name .= $splitted[$i];
						$i++;
					}

					$use_name = _stringToModName($use_name);
					if ($use_name !~ $not_valid_varname && $use_name !~ /\$|\@|\%/) {
						push @uses, $use_name;
					}

				} ## end if ($splitted[$i] !~ /\$|\@|\%/)

			} ## end elsif (($#splitted >= $i + 3) && join...)

			$i += ($before - $after);
		} else {
			$ignore{$i} = 1;
		}

		if ($is_q_function) {
			$i++ if ($splitted[$i] eq '\\');

			if ($is_eol && !$eol_next_line) {
				if (($i + length($eol_delimiter) <= $#splitted) && join('', map {$splitted[$_]} $i - 1 .. $i + length($eol_delimiter)) =~ /\R\Q$eol_delimiter\E\R/) {
					$is_q_function = 0;
					$is_eol        = 0;
					$eol_next_line = 0;
				}

			} else {

				if (($#splitted >= $i + 1) && $splitted[$i + 1] eq $q_delimiter && $splitted[$i] ne '\\') {
					if ($s_counter) {

						if ($s_counter == 2) {
							$s_counter         = 0;
							$is_q_function     = 0;
							$q_delimiter       = '';
							$q_delimiter_begin = '';
							$i++;
						} else {
							$s_counter++;
						}

					} else {
						$is_q_function     = 0;
						$q_delimiter       = '';
						$q_delimiter_begin = '';
						$i++;
					} ## end else [ if ($s_counter) ]

				} elsif (::re::is_regexp($q_delimiter) && $splitted[$i + 1] =~ $q_delimiter) {
					$is_q_function     = 0;
					$q_delimiter       = '';
					$q_delimiter_begin = '';
					$add_string        = '';
					$i++;
				} ## end elsif (::re::is_regexp($q_delimiter...))

			} ## end else [ if ($is_eol && !$eol_next_line) ]

		} ## end if ($is_q_function)

		_afterMatching(\$regex_started, \$i, $is_q_function, \@splitted);
	} ## end while ($i <= $#splitted)

	if ($revert) {
		foreach my $tmod (map {createModuleName($_)} @uses) {
			next unless $tmod;
			push @uses, $tmod;
		}

	} ## end if ($revert)

	foreach (0 .. $#uses) {
		delete $uses[$_] if $uses[$_] =~ $ignore_regex;
	}

	{
		@uses = grep {defined($_)} @uses;
		my %hash = map {$_ => 1} @uses;
		@uses = keys %hash;
	}

	my @not_used_but_used = ();

	foreach my $this_use (@uses) {
		if (!grep($_ eq $this_use, @really_used)) {
			push @not_used_but_used, $this_use;
		}

	} ## end foreach my $this_use (@uses)

	@not_used_but_used = grep {defined $_ && length($_) >= 1} @not_used_but_used;
	return @not_used_but_used;
} ## end sub findNeededUses

sub _isQFunction {
	my ($i, $regex_started, $s_counter, $splitted, $ignore_arrow, $is_eol, $eol_delimiter, $eol_next_line) = @_;
	my ($add_string, $q_delimiter, $q_delimiter_begin, $is_regex, $is_q_function) = ('', '', '', 0, 0, '');

	if ((($i + 1) <= $#{$splitted}) && ($splitted->[$i] eq '=' || $splitted->[$i] eq '!') && $splitted->[$i + 1] eq '~') {
		$regex_started = 1;
		$add_string .= $splitted->[$i] . '~';
		$i += 2;
	} ## end if ((($i + 1) <= $#{$splitted}) ...)

	if ($splitted->[$i] eq '=' && (($i + 1) <= $#{$splitted}) && $splitted->[$i + 1] eq '>') {
		if ($ignore_arrow) {
			$ignore_arrow = 0;
		} else {
			$ignore_arrow = 1;
			my $old_i      = $i;
			my $seen_chars = 0;
			my $done       = 0;

			while (!$done) {
				$i--;

				if (!$seen_chars) {
					$seen_chars = 1 if $splitted->[$i] =~ /[\w\$]/;
				}

				if (!$seen_chars && $splitted->[$i] !~ /\s/ && $splitted->[$i] =~ /\W/) {
					$i = $old_i;
					last;
				}

				if ($seen_chars && ($i == 0 || $splitted->[$i] =~ /\W/)) {
					$done = 1;
					last;
				}

			} ## end while (!$done)

			if ($i != $old_i) {
				$q_delimiter = $arrow_pseudo_delimiter;
			}

		} ## end else [ if ($ignore_arrow) ]

	} elsif (!$is_eol && ($i + 2) <= $#{$splitted} && $splitted->[$i] . $splitted->[$i + 1] eq '<<') {
		$i += 2;
		my $skip = 0;

		if ($splitted->[$i] =~ /\W/) {
			$skip = 1;
			$i++;
		}

		while ($splitted->[$i] =~ /[a-zA-Z0-9_]/) {
			$q_delimiter .= $splitted->[$i];
			last if (($i + 1) >= $#{$splitted});
			$i++;
		} ## end while ($splitted->[$i] =~ /[a-zA-Z0-9_]/)

		$i++;
		$add_string .= '<<' . $q_delimiter;
		$is_eol        = 1;
		$eol_next_line = 1;
	} elsif ($splitted->[$i] eq 'q' && (($i > 0 && $splitted->[$i - 1] =~ $not_valid_varname) || $i == 0)) {

		if ($splitted->[$i + 1] =~ /(?:q|x|r|w)/) { 
			my $detail = $splitted->[$i + 1];

			if ($#{$splitted} >= $i + 2 && $splitted->[$i + 2] =~ $not_valid_varname && $splitted->[$i + 2] !~ /\s/) {
				$i += 2;
				$add_string .= "q$detail";
				$q_delimiter = $splitted->[$i];
			} elsif ($#{$splitted} >= $i + 2 && $splitted->[$i + 2] =~ /\s/ && $splitted->[$i + 3] =~ $not_valid_varname) {
				$i += 3;
				$add_string .= "q$detail ";
				$q_delimiter = $splitted->[$i];
			}

		} elsif ($splitted->[$i + 1] =~ $not_valid_varname) { 
			$i++;
			$add_string .= 'q';
			$q_delimiter = $splitted->[$i];
		} elsif ($splitted->[$i + 1] =~ /\s/ && $splitted->[$i + 2] =~ $not_valid_varname) { 
			$i += 3;
			$add_string .= 'q ';
			$q_delimiter = $splitted->[$i];
		}

		if (($#{$splitted} >= $i + 1) && $splitted->[$i] . $splitted->[$i + 1] eq '=>') {
			$q_delimiter = undef;
		}

	} elsif ($regex_started) {
		my $before = $i;
		_skip_whitespace $i, $splitted;
		$add_string .= ' ' x ($i - $before);

		if (($i > 0 && $splitted->[$i - 1] =~ $not_valid_varname) || $i == 0) {
			while ($splitted->[$i] =~ /\s/) {$i++}

			if ($splitted->[$i] eq 'm' && $splitted->[$i + 1] =~ $not_valid_varname) { 
				$i++;
				$add_string .= 'm';
				$q_delimiter = $splitted->[$i];
				$is_regex    = 1;
			} elsif (($i == 0 || ($i >= 1 && $splitted->[$i - 1] !~ /\*|\$|\%|\@|\&/)) && $splitted->[$i] eq 's' && $splitted->[$i + 1] =~ $not_valid_varname) {
				$i++;
				$add_string .= 's';
				$q_delimiter = $splitted->[$i];
				$s_counter++;
				$is_regex = 1;
			} elsif ($splitted->[$i] eq '/') { 
				my $str = '';
				{
					my $last_var = $i;
					_skip_to_whitespace_reverse $last_var, $splitted;
					$last_var--;

					while ($splitted->[$last_var] !~ /\s|;|\{/) {
						$str = "$splitted->[$last_var]$str";
						$last_var--;
					}

				}

				if ($str !~ /^(?:\$|\@|\%)/ && $str !~ /[0-9]*(?:\.[0-9]*)/) {
					$q_delimiter = $splitted->[$i];
					$add_string .= '/';
					$is_regex = 1;
				} ## end if ($str !~ /^(?:\$|\@|\%)/ && $str...)

			} elsif ($splitted->[$i] eq 't' && $splitted->[$i + 1] eq 'r') {
				if ($splitted->[$i + 2] =~ $not_valid_varname) {
					$i += 2;
					$add_string .= 'tr';
					$s_counter++;
					$q_delimiter = $splitted->[$i];
					$is_regex    = 1;
				} ## end if ($splitted->[$i + 2] =~ $not_valid_varname)

			} elsif ($splitted->[$i] eq 'y' && $splitted->[$i + 1] =~ $not_valid_varname) {
				if ($splitted->[$i + 1] =~ $not_valid_varname) { # y
					$i++;
					$add_string .= 'y';
					$s_counter++;
					$q_delimiter = $splitted->[$i];
					$is_regex    = 1;
				} ## end if ($splitted->[$i + 1] =~ $not_valid_varname)

			} elsif ($splitted->[$i] eq '"') {
				$q_delimiter = '"';
			} elsif ($splitted->[$i] eq q#'#) {
				$q_delimiter = q#'#;
			} elsif ($splitted->[$i] eq 'q' && (($i > 0 && $splitted->[$i - 1] =~ $not_valid_varname) || $i == 0)) {

				if ($splitted->[$i + 1] =~ /(?:q|x|r|w)/) {
					my $detail = $splitted->[$i + 1];

					if ($splitted->[$i + 2] =~ $not_valid_varname && $splitted->[$i + 2] !~ /\s/) {
						$i += 2;
						$add_string .= "q$detail";
						$q_delimiter = $splitted->[$i];
					} elsif ($splitted->[$i + 2] =~ /\s/ && $splitted->[$i + 3] =~ $not_valid_varname) {
						$i += 3;
						$add_string .= "q$detail ";
						$q_delimiter = $splitted->[$i];
					}

				} elsif ($splitted->[$i + 1] =~ $not_valid_varname) {
					$i++;
					$add_string .= 'q';
					$q_delimiter = $splitted->[$i];
				} elsif ($splitted->[$i + 1] =~ /\s/ && $splitted->[$i + 2] =~ $not_valid_varname) {
					$i += 3;
					$add_string .= 'q ';
					$q_delimiter = $splitted->[$i];
				}

			} else {
				$i          = $before;
				$add_string = '';
			}

		} ## end if (($i > 0 && $splitted->[$i - ...]))

	} elsif ($i == 0 || ($i > 0 && $splitted->[$i - 1] ne '$' && ($splitted->[$i - 1] ne '\\' || $splitted->[$i - 2] . $splitted->[$i - 1] eq '\\\\'))) {
		if ($splitted->[$i] eq q#"#) {
			$q_delimiter = q#"#;
		} elsif ($splitted->[$i] eq q#'#) { 
			$q_delimiter = q#'#;
		} elsif ($splitted->[$i] eq q#`#) { 
			$q_delimiter = q#`#;
		} elsif (!$q_delimiter
			&& (scalar @$splitted - 1) >= ($i + 1)
			&& (($i > 0 && $splitted->[$i - 1] !~ /\$|\@|\%|\*|[a-zA-Z0-9_]/ && $splitted->[$i - 1] =~ /\s|\(|\{/) || $i == 0)
			&& ($splitted->[$i + 1] !~ /[a-zA-Z0-9_]/ || ($splitted->[$i] . $splitted->[$i + 1] eq 'tr' && $splitted->[$i + 2] !~ /[a-zA-Z0-9_]/))) {

			if (   ((($#{$splitted} >= $i - 2) && $splitted->[$i - 1] ne '&' && $splitted->[$i - 1] . $splitted->[$i - 2] ne '::') || $i == 0)
				&& (($i + 2) <= $#{$splitted} && $splitted->[$i + 1] . $splitted->[$i + 2] ne '=>')) {

				if (($splitted->[$i] eq 's' || $splitted->[$i] eq 'y' || $splitted->[$i] eq 'm')) {

					$add_string = $splitted->[$i];
					$i++;
					my $str      = '';
					my $last_var = $i;
					$last_var--;

					while ($splitted->[$last_var] =~ /\s/) {
						$last_var--;
						last if ($last_var < 0);
					}

					while ($splitted->[$last_var] !~ /\t|\n| |\{|=/) {
						last if (($last_var - 1) < 0);
						$str = "$splitted->[$last_var]$str";
						$last_var--;
					} ## end while ($splitted->[$last_var] !~ /\t|\n| |\{|=/})

					$str = "$splitted->[$last_var]$str" if $splitted->[$last_var] !~ /\{/;
					$str =~ s/(?:^\s*)|(?:\s$)//g;

					if ((!$str && join('', map {$splitted->[$_]} $last_var + 1 .. $i - 1) =~ /^\n*$/) || $str !~ /^(?:\$|\@|\%)/ && $str !~ /(?:-)?[0-9]*(?:\.[0-9]?)/ && $str) {
						if ($str !~ /\{|\}|\[|\]/ || ($splitted->[$last_var - 2] . $splitted->[$last_var - 1] !~ /->/ && $str !~ /\{|\}|\[|\]/)) {

							if ($splitted->[$i - 1] eq 's' || $splitted->[$i] eq 'y') {
								$s_counter++;
							}

							unless ($splitted->[$i] . $splitted->[$i + 1] eq '=>') {
								$q_delimiter = $splitted->[$i];
								$is_regex    = 1;
							}

						} ## end if ($str !~ /\{|\}|\[|\]/ || ($splitted...))

					} ## end if ((!$str && join('', map {$splitted...})))

				} elsif (($splitted->[$i] eq 't' && $splitted->[$i + 1] eq 'r') && $splitted->[$i - 1] ne '&') {

					# implizierter tr-regex-match auf $_ (tr/a/b/)
					$add_string = $splitted->[$i];
					$i++;
					my $str      = '';
					my $last_var = $i;
					$last_var = ($last_var - 2 >= 0) ? $last_var - 2 : 0;

					while ($splitted->[$last_var] =~ /\s/) {
						last if ($last_var - 1 < 0);
						$last_var--;
					}

					while ($splitted->[$last_var] !~ /\t|\n| |\{|=|;/) {
						last if (($last_var - 1) < 0);
						$str = "$splitted->[$last_var]$str";
						$last_var--;
					} ## end while ($splitted->[$last_var] !~ /\t|\n| |\{|=|;/})

					$str = "$splitted->[$last_var]$str" if ($splitted->[$last_var] !~ /\{/ && $last_var != $i - 1);
					$str =~ s/(?:^\s*)|(?:\s$)//g;

					if ((!$str && join('', map {$splitted->[$_]} $last_var + 1 .. $i - 1) =~ /^\n*$/) || $str !~ /^(?:\$|\@|\%)/ && $str !~ /(?:-)?[0-9]*(?:\.[0-9]?)/ && $str) {
						if ($str !~ /\{|\}|\[|\]/ || ($splitted->[$last_var - 2] . $splitted->[$last_var - 1] !~ /->/ && $str !~ /\{|\}|\[|\]/)) {

							unless ($splitted->[$i] . $splitted->[$i + 1] eq '=>') {
								$s_counter++;
								$add_string .= $splitted->[$i];
								$q_delimiter = $splitted->[++$i];
								$is_regex    = 1;
							} ## end unless ($splitted->[$i] . $splitted->...)

						} ## end if ($str !~ /\{|\}|\[|\]/ || ($splitted...))

					} ## end if ((!$str && join('', map {$splitted...})))

				} elsif ($splitted->[$i] eq '/') {
					my $str      = '';
					my $last_var = $i;
					$last_var--;

					while ($splitted->[$last_var] =~ /\s/) {
						$last_var--;
						last if ($last_var < 0);
					}

					while ($splitted->[$last_var] !~ /\t|\n| |\{|;|=|\(/) {
						last if (($last_var - 1) < 0);
						$str = "$splitted->[$last_var]$str";
						$last_var--;
					} ## end while ($splitted->[$last_var] !~ /\t|\n| |\{|;|=|\(/)})

					$str =~ s#/##;
					$str = "$splitted->[$last_var]$str" if $splitted->[$last_var] !~ /\(/;
					$str =~ s/(?:^\s*)|(?:\s$)//g;

					if ((!$str && join('', map {$splitted->[$_]} $last_var + 1 .. $i - 1) =~ /^\n*$/)
						|| $str !~ /(?:\$|\@|\%|\*|\+|-|\\)/ && $str !~ /^(?:-)?[0-9]+(?:\.[0-9]*)?$/ && $str && $str !~ /<|>|"|'|\)/) {

						if ($str !~ /\{|\}|\[|\]/ || ($splitted->[$last_var - 2] . $splitted->[$last_var - 1] !~ /->/ && $str !~ /\{|\}|\[|\]/)) {
							unless ($splitted->[$i] . $splitted->[$i + 1] eq '=>') {
								$q_delimiter = $splitted->[$i];
								$is_regex    = 1;
							}

						} ## end if ($str !~ /\{|\}|\[|\]/ || ($splitted...))

					} ## end if ((!$str && join('', map {$splitted...})))

				} ## end elsif ($splitted->[$i] eq '/')

			} ## end if (((($#{$splitted} >= $i - 2) ...)))

		} elsif ($splitted->[$i] eq '{') {
			my $tmp_i = $i - 1;
			my $prev  = '';

			while ($splitted->[$tmp_i] !~ /\s|;|\(|\)|=/) {
				last if $tmp_i <= 0;
				$prev = "$splitted->[$tmp_i]$prev";
				$tmp_i--;
			} ## end while ($splitted->[$tmp_i] !~ /\s|;|\(|\)|=/)

			$prev = "$splitted->[$tmp_i]$prev" if $splitted->[$tmp_i] =~ /\$|\*|\@|\%|[a-zA-Z0-9_]/;
			if ($prev =~ /(?:\$|\%|\@|\%)./ && $prev !~ /->/) {
				$q_delimiter = $splitted->[$i];
			}

		} ## end elsif ($splitted->[$i] eq '{') (})

	} ## end elsif ($i == 0 || ($i > 0 && $splitted...))

	# setze passenden gegen-delimiter bei klammer-tags ( qr(), qr{}, qr<>, ...)
	if ($q_delimiter) {
		$q_delimiter_begin = $q_delimiter;
		$q_delimiter       = _getDelimiter($q_delimiter);

		if ($q_delimiter !~ /[a-zA-Z0-9_]/ || ::re::is_regexp($q_delimiter)) {
			$is_q_function = 1;
			$regex_started = 0;
		} elsif ($is_eol && $q_delimiter =~ /[a-zA-Z0-9_]/) {
			$is_q_function = 0;
			$regex_started = 0;
			$eol_delimiter = $q_delimiter;
			$q_delimiter   = '';
		} ## end elsif ($is_eol && $q_delimiter =~ /[a-zA-Z0-9_]/)

	} ## end if ($q_delimiter)

	return ($is_q_function, $i, $regex_started, $q_delimiter, $s_counter, $add_string, $q_delimiter_begin, $is_regex, $ignore_arrow, $is_eol, $eol_next_line, $eol_delimiter);
} ## end sub _isQFunction

sub getPackages {
	my $code = shift;
	return unless $code;
	$code = stripComments($code);
	my @packages = ();
	@packages = $code =~ /(?:^|\n|\r)package\s+?([a-zA-Z0-9\:]+?);/g;
	return @packages;
} ## end sub getPackages

sub createPerlModuleName {
	my $filename = shift;
	my $use_name = '';

	if ($filename =~ m#^/#) {
		foreach my $modpart (@INC) {

			if ($filename =~ /^$modpart/) {
				$use_name = $filename;
				$use_name =~ s/$modpart//g;
				$use_name =~ s/\//::/g;
				$use_name =~ s/\.pm$//g;
				last;
			} ## end if ($filename =~ /^$modpart/)

		} ## end foreach my $modpart (@INC)

	} else {

		foreach my $modpart (@INC) {
			if (-e "$modpart/$filename") {
				$use_name = $filename;
				$use_name =~ s/$modpart//g;
				$use_name =~ s/\//::/g;
				$use_name =~ s/\.pm$//g;
				last;
			} ## end if (-e "$modpart/$filename")

		} ## end foreach my $modpart (@INC)

	} ## end else [ if ($filename =~ m#^/#) ]

	$use_name =~ s/(?:^::)|(?:::$)//g;
	return $use_name;
} ## end sub createPerlModuleName

sub getExportedSubs {
	my $modul = shift;
	my $mod_is_code = shift || 0;
	$mod_is_code = 1 if $modul =~ /\R/;
	return unless $modul;
	$modul = createModuleName($modul) unless $mod_is_code;
	return unless $modul;
	my @exports = ();
	my $code = $mod_is_code ? $modul : openFile($modul);
	$code = stripComments($code);

	foreach ($code =~ /\@EXPORT\s*=\s*(.+?);/sg) {
		my $one = $1;
		next unless defined $one;

		if ($one =~ /::/) {
			$one =~ s/\s*\((.*)\)/$1/g;

			foreach my $wert (split(/\s*,\s*/, $one)) {
				if ($wert =~ /(?:\@|\$|\%|\*)(.*)::EXPORT/) {
					my $modname = createModuleName($1);

					if ($modname) {
						push @exports, getExportedSubs($modname);
					}

				} else {
					push @exports, $wert;
				}

			} ## end foreach my $wert (split(/\s*,\s*/, $one...))

		} else {
			eval "push \@exports, $1;";
		}

	} ## end foreach ($code =~ /\@EXPORT\s*=\s*(.+?);/sg)

	foreach ($code =~ /\@EXPORT_OK\s*=(.+?);/sg) {
		my $one = $1;
		next unless defined $one;

		if ($one =~ /::/) {
			$one =~ s/\s*\((.*)\)/$1/g;

			foreach my $wert (split(/\s*,\s*/, $one)) {
				if ($wert =~ /(?:\@|\$|\%|\*)(.*)::EXPORT/) {
					my $modname = createModuleName($1);

					if ($modname) {
						push @exports, getExportedSubs($modname);
					}

				} else {
					push @exports, $wert;
				}

			} ## end foreach my $wert (split(/\s*,\s*/, $one...))

		} else {
			eval "push \@exports, $1;";
		}

	} ## end foreach ($code =~ /\@EXPORT_OK\s*=(.+?);/sg)

	if (!$mod_is_code) {
		if (exists($xs_exports{$modul})) {
			push @exports, @{$xs_exports{$modul}};
		} elsif (exists($xs_exports{createPerlModuleName($modul)})) {
			push @exports, @{$xs_exports{createPerlModuleName($modul)}};
		}

	} ## end if (!$mod_is_code)

	return @exports;
} ## end sub getExportedSubs

sub _getDelimiter {
	my $del = shift;

	if ($del eq '{') {
		$del = '}';
	} elsif ($del eq '(') {
		$del = ')';
	} elsif ($del eq '<') {
		$del = '>';
	} elsif ($del eq '[') {
		$del = ']';
	}

	return $del;
} ## end sub _getDelimiter

sub createModuleName {
	my $name = shift;
	return unless $name;
	return $name if $name =~ m#^/#;
	$name =~ s#::#/#g;

	foreach my $this_inc (@INC) {
		next if $this_inc eq '.';
		my $this_inc_name = "$this_inc/$name.pm";
		$this_inc_name =~ s/(?:\n|\r)*//g;

		if (-e $this_inc_name) {
				return $this_inc_name;
		} ## end if (-e $this_inc_name)

	} ## end foreach my $this_inc (@INC)

	return undef;
} ## end sub createModuleName


sub getSubs {
	my $mod = shift;
	my $code = shift || '';

	if (!$code && $mod) {
		unless (-e $mod) {
			$mod = createModuleName($mod, 0);
		}

		$code = openFile($mod);
	} ## end if (!$code && $mod)

	return unless $code;
	my (%subs, %subPrototypes);
	$code =~ s/(?:^|\n|\r)__(?:DATA|END)__.*//sg;
	$code =~ s#(?:\R|^)(?:=.+?)\R=cut(?:\R|$)#"\n"x((${^MATCH}=~tr{\n|\r}{}))#segp;
	my @splitted          = split('', $code);
	my $i                 = 0;
	my $is_q_function     = 0;
	my $q_delimiter       = ''; 
	my $q_delimiter_begin = '';
	my $s_counter         = 0; 
	my $is_comment        = 0;
	my $regex_started     = 0;
	my $is_regex          = 0;
	my $ignore_arrow      = 0;
	my $eol_next_line     = 0;
	my $is_eol            = 0;
	my $eol_delimiter     = '';
	my $add_string        = '';
	my $sub_name          = '';
	my $bracket_counter   = 0;
	my $ended_string      = 0;

	while ($i <= $#splitted) {

		if (!$is_comment && !$is_q_function && !$regex_started && !$ended_string) {
			($is_q_function, $i, $regex_started, $q_delimiter, $s_counter, $add_string, $q_delimiter_begin, $is_regex, $ignore_arrow, $is_eol, $eol_next_line, $eol_delimiter) =
			  _isQFunction($i, $regex_started, $s_counter, \@splitted, $ignore_arrow, $is_eol, $eol_delimiter, $eol_next_line);
		}

		$ended_string = 0 if ($ended_string);
		if ($splitted[$i] eq "\n" || $splitted[$i] eq "\r") {
			$is_comment = 0;

			if ($eol_next_line == 1) {
				$is_q_function = 1;
				$eol_next_line = 0;
			}

		} ## end if ($splitted[$i] eq "\n" || $splitted...)

		if (!$is_q_function && $splitted[$i - 1] ne '$') { 
			if ($splitted[$i] eq '#') {
				$is_comment = 1;
			} ## end if ($splitted[$i] eq '#')

		} ## end if (!$is_q_function && $splitted...)

		if (!$is_comment && !$is_q_function && !$sub_name) {
			if ((($i + 2) <= $#splitted) && join('', map {$splitted[$_]} $i .. $i + 2) eq 'sub') {
				$i += 3;
				_skip_whitespace $i, \@splitted;

				while ($splitted[$i] =~ /[a-zA-Z0-9_]/) {
					$sub_name .= $splitted[$i];
					$i++;
				}

				_skip_whitespace $i, \@splitted;
				unless (exists($subPrototypes{$sub_name})) {

					if ($splitted[$i] eq '(') {
						while ($splitted[$i - 1] ne ')') {
							$subPrototypes{$sub_name} .= $splitted[$i];
							$i++;
						}

					} ## end if ($splitted[$i] eq '(') )

					_skip_whitespace $i, \@splitted;
				} ## end unless (exists($subPrototypes{$sub_name...}))

				$sub_name = '' if $splitted[$i] eq ';';
			} ## end if ((($i + 2) <= $#splitted) && ...)

		} ## end if (!$is_comment && !$is_q_function...)

		if ($sub_name) {
			if (!$is_comment && !$is_q_function) {

				if ($splitted[$i] eq '{') {
					$bracket_counter++;
				} elsif ($splitted[$i] eq '}') {
					$bracket_counter--;
				}

			} ## end if (!$is_comment && !$is_q_function)

			if ($add_string) {
				$subs{$sub_name} .= $add_string;
				$add_string = '';
			}

			$subs{$sub_name} .= $splitted[$i];
			$sub_name = '' if $bracket_counter == 0;
		} ## end if ($sub_name)

		if ($is_q_function) {
			$i++ if ($splitted[$i] eq '\\');

			if ($is_eol && !$eol_next_line) {
				if (($i + length($eol_delimiter) <= $#splitted) && join('', map {$splitted[$_]} $i - 1 .. $i + length($eol_delimiter)) =~ /\R\Q$eol_delimiter\E\R/) {
					$is_q_function = 0;
					$is_eol        = 0;
					$eol_next_line = 0;
				}

			} else {

				if (($#splitted >= $i + 1) && $splitted[$i + 1] eq $q_delimiter) {
					if ($s_counter) {

						if ($s_counter == 2) {
							$s_counter         = 0;
							$is_q_function     = 0;
							$q_delimiter       = '';
							$q_delimiter_begin = '';
							$ended_string++;
						} else {
							$s_counter++;
						}

					} else {
						$is_q_function     = 0;
						$q_delimiter       = '';
						$q_delimiter_begin = '';
						$ended_string++;
					} ## end else [ if ($s_counter) ]

				} elsif (::re::is_regexp($q_delimiter) && $splitted[$i + 1] =~ $q_delimiter) {
					$is_q_function     = 0;
					$q_delimiter       = '';
					$q_delimiter_begin = '';
					$add_string        = '';
					$i++;
				} ## end elsif (::re::is_regexp($q_delimiter...))

			} ## end else [ if ($is_eol && !$eol_next_line) ]

		} ## end if ($is_q_function)

		_afterMatching(\$regex_started, \$i, $is_q_function, \@splitted);
	} ## end while ($i <= $#splitted)

	return (\%subs, \%subPrototypes);
} ## end sub getSubs

sub getUses {
	my $mod          = shift;
	my $modIsContent = shift || 0;
	my $revert       = shift;
	$revert = 1 unless defined $revert;
	my $code = '';
	$modIsContent = 1 if $mod =~ /\n/;

	if ($modIsContent) {
		$code = $mod;
	} else {
		$code = openFile($mod);
	}

	$code = stripComments($code);
	return unless $code;
	my @uses              = ();
	my @splitted          = split('', $code);
	my $i                 = 0;
	my $is_q_function     = 0;
	my $q_delimiter       = '';  
	my $q_delimiter_begin = '';
	my $s_counter         = 0;
	my $is_comment        = 0;
	my $regex_started     = 0;
	my $is_regex          = 0;
	my $ignore_arrow      = 0;
	my $eol_next_line     = 0;
	my $is_eol            = 0;
	my $eol_delimiter     = '';
	my $add_string        = '';
	my $ignore_regex = '^(?:\b' . join('\b)|(?:\b', map {quotemeta $_} @perl_pragmas) . ')$\b';
	$ignore_regex = qr/$ignore_regex/;
	my $max = $#splitted;

	while ($i <= $#splitted) {

		if ($is_comment == 0 && $is_q_function == 0 && $regex_started == 0) {
			($is_q_function, $i, $regex_started, $q_delimiter, $s_counter, $add_string, $q_delimiter_begin, $is_regex, $ignore_arrow, $is_eol, $eol_next_line, $eol_delimiter) =
			  _isQFunction($i, $regex_started, $s_counter, \@splitted, $ignore_arrow, $is_eol, $eol_delimiter, $eol_next_line);
		}

		if ($splitted[$i] eq "\n" || $splitted[$i] eq "\r") {
			$is_comment = 0;

			if ($eol_next_line == 1) {
				$is_q_function = 1;
				$eol_next_line = 0;
			}

		} ## end if ($splitted[$i] eq "\n" || $splitted...)

		if (!$is_q_function && $splitted[$i - 1] ne '$') {
			if ($splitted[$i] eq '#') {
				$is_comment = 1;
			} ## end if ($splitted[$i] eq '#')

		} ## end if (!$is_q_function && $splitted...)

		if (!$is_comment && !$is_q_function) {
			if ($splitted[$i - 1] !~ /\@|\$|\%/) {

				if ($#splitted >= ($i + 3) && ($i == 0 || $splitted[$i - 1] =~ $not_valid_varname && $splitted[$i - 1] !~ /\$|\@|\%/) && (join('', map {$splitted[$_]} $i .. $i + 3) =~ /use\s/)) {
					$i += 3;
					_skip_whitespace $i, \@splitted;

					if ($i + 3 <= $#splitted && join('', map {$splitted[$_]} $i .. $i + 3) eq 'base') {
						$i += 4;
					}

					_skip_whitespace $i, \@splitted;
					my $use_name = '';

					while ($splitted[$i] !~ /\s|;/) {
						$use_name .= $splitted[$i];
						last if (($i + 1) > $#splitted);
						$i++;
						last if $i > $#splitted;
					} ## end while ($splitted[$i] !~ /\s|;/)

					if ($use_name && $use_name !~ /^(?:[0-9\.]+)$/ && $use_name !~ $ignore_regex && $use_name !~ /\$|\@|\%/) {
						if ($use_name =~ $not_valid_varname && $use_name =~ /^(?:q|'|")/) {
							push @uses, eval "$use_name";
						} else {
							push @uses, $use_name;
						}

					} ## end if ($use_name && $use_name !~ /^(?:[0-9\.]+)$/...)

				} elsif (
					$#splitted >= ($i + 6) && ($i == 0 || $splitted[$i - 1] =~ $not_valid_varname && $splitted[$i - 1] !~ /\$|\@|\%/) && (
						join(
							'',
							map {
								$splitted[$_]
							} $i .. $i + 6
						) =~ /use_ok\W/
					)
				  ) {

					$i += 6;
					_skip_whitespace $i, \@splitted;

					if ($i + 3 <= $#splitted && join('', map {$splitted[$_]} $i .. $i + 3) eq 'base') {
						$i += 4;
					}

					_skip_whitespace $i, \@splitted;
					my $use_name = '';

					while ($splitted[$i] !~ /\s|;/) {
						$use_name .= $splitted[$i];
						last if (($i + 1) > $#splitted);
						$i++;
						last if $i > $#splitted;
					} ## end while ($splitted[$i] !~ /\s|;/)

					$use_name =~ s/\((?:q(?:q|x|w)?)?\W(.*)\W\)/$1/;

					if ($use_name && $use_name !~ /^(?:[0-9\.]+)$/ && $use_name !~ $ignore_regex && $use_name !~ /\$|\@|\%/) {
						if ($use_name =~ $not_valid_varname && $use_name =~ /^(?:q|'|")/) {
							push @uses, eval "$use_name";
						} else {
							push @uses, $use_name;
						}

					} ## end if ($use_name && $use_name !~ /^(?:[0-9\.]+)$/...)

				} elsif (
					$#splitted >= ($i + 7) && ($i == 0 || $splitted[$i - 1] =~ $not_valid_varname && $splitted[$i - 1] !~ /\$|\@|\%/) && (
						join(
							'',
							map {
								$splitted[$_]
							} $i .. $i + 7
						) =~ /require\s/
					)
				  ) {

					$i += 7;
					_skip_whitespace $i, \@splitted;
					my $use_name = '';

					while ($splitted[$i] ne ';') {
						$use_name .= $splitted[$i];
						last if (($i + 1) > $#splitted);
						$i++;
					} ## end while ($splitted[$i] ne ';')

					my $old_use_name = $use_name;
					$use_name = _removeQuotelikeFromString($use_name);

					if ($old_use_name ne $use_name) {
						$use_name = createPerlModuleName($use_name);
					}

					push @uses, $use_name if $use_name !~ /\$|\@|\%/ && $use_name =~ /^[a-zA-Z0-9:_-]+$/;
				} elsif (
					$#splitted >= ($i + 3) && ($i == 0 || $splitted[$i - 1] =~ $not_valid_varname && $splitted[$i - 1] !~ /\$|\@|\%/) && (
						join(
							'',
							map {
								$splitted[$_]
							} $i .. $i + 3
						) eq '@ISA'
					)
				  ) {

					$i += 4;
					_skip_whitespace $i, \@splitted;
					my $use_name = '';

					while ($splitted[$i] !~ /;/) {
						$use_name .= $splitted[$i];
						last if (($i + 1) > $#splitted);
						$i++;
					} ## end while ($splitted[$i] !~ /;/)

					push @uses, eval "$use_name" if $use_name !~ /\$|\@|\%/ && $use_name =~ /^[a-zA-Z0-9:_-]+$/;
				} ## end elsif ($#splitted >= ($i + 3) && ($i...))

			} ## end if ($splitted[$i - 1] !~ /\@|\$|\%/)

		} ## end if (!$is_comment && !$is_q_function)

		if ($is_q_function) {
			$i++ if ($splitted[$i] eq '\\');

			if ($max >= $i + 1) {
				if ($is_eol && !$eol_next_line) {

					if (($i + length($eol_delimiter) <= $#splitted) && join('', map {$splitted[$_]} $i - 1 .. $i + length($eol_delimiter)) =~ /\R\Q$eol_delimiter\E\R/) {
						$is_q_function = 0;
						$is_eol        = 0;
						$eol_next_line = 0;
					} ## end if (($i + length($eol_delimiter)...))

				} else {

					if ($splitted[$i + 1] eq $q_delimiter) {
						if ($s_counter) {

							if ($s_counter == 2) {
								$s_counter         = 0;
								$is_q_function     = 0;
								$q_delimiter       = '';
								$q_delimiter_begin = '';
								$i++;
							} else {
								$s_counter++;
							}

						} else {
							$is_q_function     = 0;
							$q_delimiter       = '';
							$q_delimiter_begin = '';
							$i++;
						} ## end else [ if ($s_counter) ]

					} elsif (::re::is_regexp($q_delimiter) && $splitted[$i + 1] =~ $q_delimiter) {
						$is_q_function     = 0;
						$q_delimiter       = '';
						$q_delimiter_begin = '';
						$add_string        = '';
						$i++;
					} ## end elsif (::re::is_regexp($q_delimiter...))

				} ## end else [ if ($is_eol && !$eol_next_line) ]

			} ## end if ($max >= $i + 1)

		} ## end if ($is_q_function)

		_afterMatching(\$regex_started, \$i, $is_q_function, \@splitted);
	} ## end while ($i <= $#splitted)

	my @uses_new = ();
	if ($revert) {

		foreach my $tmod (map {createModuleName($_)} @uses) {
			next unless $tmod;
			push @uses_new, $tmod;
		}

	} else {
		@uses_new = @uses;
	}

	@uses_new = grep {defined($_)} @uses_new;
	foreach (0 .. $#uses_new) {
		delete $uses_new[$_] if $uses_new[$_] =~ /$ignore_regex/o;
	}

	@uses_new = map {my $x = $_; $x =~ s/\/{2,}/\//g; $x} grep {defined($_)} @uses_new;
	return @uses_new;
} ## end sub getUses

sub _afterMatching {
	my ($regex_started, $i, $is_q_function, $splitted) = @_;
	my $char = $splitted->[$$i];

	if ($$regex_started && exists($splitted->[$$i])) {
		if (
			$char eq ';'
			|| (
				!$is_q_function
				&& (
					   $char eq ')'
					|| $char eq '}'
					|| (   $$i >= 1
						&& ($#{$splitted} >= $$i + 1)
						&& $splitted->[$$i - 1] =~ m#\s#
						&& (($char . $splitted->[$$i + 1] =~ /\|\||&&|or/) || (($#{$splitted} >= $$i + 2) && $char eq 'a' && $splitted->[$$i + 1] eq 'n' && $splitted->[$$i + 2] eq 'd')))
				)
			)
		  ) {
			$$regex_started = 0;
		} ## end if ($char eq ';' || (!$is_q_function...))

	} ## end if ($$regex_started && exists($splitted...))

	$$i = $$i + 1;
} ## end sub _afterMatching

sub getUnnecessaryUses {
	my ($code, $already_stripped_comments) = @_;
	return unless $code;
	$code = FindNeedlessUses::stripComments($code) unless $already_stripped_comments;
	my @uses         = FindNeedlessUses::getUses($code, 1, 0, 1);
	my @unnessessary = ();
	my $ignore_regex = join('\b|\b', map {quotemeta($_)} @perl_pragmas);
	$ignore_regex = qr/\b(?:$ignore_regex|5[\.\d_]+?)\b/;

	foreach my $mod (@uses) {
		my $mo = quotemeta($mod);
		$code =~ s/(?:us|requir)e\s+?$mo//g;
		next if $mo =~ $ignore_regex;
		my ($subs, $prototypes) = getSubs($mod);
		my $all_functions = join('|', map {quotemeta $_} keys %{$subs});
		my $exported_subs_regex = defined($mod) ? join('|', map {quotemeta $_} getExportedSubs($mod)) : '';
		my @packages            = getPackages(openFile(createModuleName($mod)));
		my $packages_list       = join('|', map {quotemeta $_} @packages);
		my $mo_package_list     = $mo;

		if ($packages_list) {
			$mo_package_list .= '|' . $packages_list;
		}

		if (
			$code !~ /\b(?:$mo_package_list)(?:->|::)(?:$all_functions)?/ &&
			$code !~ $exported_subs_regex                                 &&
			$code !~ /new (?:$mo_package_list)/                           &&
			$code !~ /(?:$mo_package_list)->new/                          &&
			$code !~ /(?:\$)(?:main::)?(?:$mo_package_list)/
		  ) { 
			push @unnessessary, $mod;
		} ## end if ($code !~ /\b(?:$mo_package_list)(?:->|::)(?:$all_functions)?/...)

	} ## end foreach my $mod (@uses)

	return @unnessessary;
} ## end sub getUnnecessaryUses

sub _removeQuotelikeFromString {
	my $str = shift;

	if ($str =~ /^(?:"|')/) {
		$str =~ s/(?:^(?:'|"))|(?:(?:'|")$)//g;
	} elsif ($str =~ /^q[^\w]/) {
		$str =~ s/^q([^\w])//g;
		my $del = _getDelimiter($1);
		$str =~ s/\Q$del\E$//g;
	} elsif ($str =~ /^q(?:x|w|q|r)/) {
		$str =~ s/^q(?:x|w|q|r)(.)//g;
		my $del = _getDelimiter($1);
		$str =~ s/\Q$del\E$//;
	}

	return $str;
} ## end sub _removeQuotelikeFromString

sub _stringToModName {
	my $string = shift;
	return '' unless $string;
	my $modname = '';
	$modname = createModuleName($string);
	return $string if $modname;

	if ($string =~ /->/) {
		$string =~ s/(.*)->.+?$/$1/;
		return _stringToModName($1);
	} elsif ($string =~ /(.*)::.+?\(/) {
		return _stringToModName($1);
	} elsif ($string =~ /(.*)::.+?/) {
		return _stringToModName($1);
	} else {
		return '';
	}

} ## end sub _stringToModName

sub listFiles {
	my $folder    = shift;
	my $regex     = shift || qr(\.pm$);
	my $recursive = shift || 1;

	unless (ref $regex eq 'Regexp') {
		$regex = qr/$regex/;
	}

	my @files = ();
	opendir(my $MODULES, $folder) || die $!;

	foreach my $file (readdir($MODULES)) {
		next if $file eq '.';
		next if $file eq '..';
		my $path = "$folder/$file";

		if (-d $path) {
			if ($recursive) {
				push @files, listFiles($path, $regex);
			}

		} ## end if (-d $path)

		if (-f $path) {
			push @files, $path if $path =~ $regex;
		}

	} ## end foreach my $file (readdir($MODULES))

	closedir $MODULES || warn "=> $folder, $! \n";
	my %hash = map {$_ => 1} @files;
	@files = keys %hash;
	return @files;
} ## end sub listFiles

sub _fill_internal_data () {
	my $name = '';

	while (my $data = <DATA>) {
		if ($data =~ /^\w/) {
			$name = $data;
			$name =~ s/\s*$//g;
		} else {
			my $this_export = $data;
			$this_export =~ s/^\s*|\s*$//g;
			push @{$xs_exports{$name}}, $this_export if $this_export;
		}

	} ## end while (my $data = <DATA>)

	# Not really modules, more like "compiler-directives"
	@perl_pragmas = qw/
	  warnings
	  Exporter
	  diagnostics
	  strict
	  Carp
	  base
	  Switch
	  constant
	  lib
	  feature
	  vars
	  utf8
	  warnings::register
	  sort
	  subs
	  UNIVERSAL
	  CORE
	  re
	  parent
	  overload
	  overloading
	  ops
	  open
	  mro
	  locale
	  less
	  integer
	  if
	  filetest
	  fields
	  encoding
	  names
	  bytes
	  blib
	  bigrat
	  bignum
	  bigint
	  autouse
	  autodie
	  attributes
	  threads
	  thread::shared
	  vmsish
	  sigtrap
	  /;

	# done
} ## end sub _fill_internal_data



1;

__DATA__
POSIX
	abort
	abs
	access
	acos
	alarm
	asctime
	asin
	assert
	atan
	atan2
	atexit
	atof
	atoi
	atol
	bsearch
	calloc
	ceil
	chdir
	chmod
	chown
	clearerr
	clock
	close
	closedir
	cos
	cosh
	creat
	ctermid
	ctime
	cuserid
	difftime
	div
	dup
	dup2
	errno
	execl
	execle
	execlp
	execv
	execve
	execvp
	_exit
	exit
	exp
	fabs
	fclose
	fcntl
	fdopen
	feof
	ferror
	fflush
	fgetc
	fgetpos
	fgets
	fileno
	floor
	fmod
	fopen
	fork
	fpathconf
	fprintf
	fputc
	fputs
	fread
	free
	freopen
	frexp
	fscanf
	fseek
	fsetpos
	fstat
	fsync
	ftell
	fwrite
	getc
	getchar
	getcwd
	getegid
	getenv
	geteuid
	getgid
	getgrgid
	getgrnam
	getgroups
	getlogin
	getpgrp
	getpid
	getppid
	getpwnam
	getpwuid
	gets
	getuid
	gmtime
	isalnum
	isalpha
	isatty
	iscntrl
	isdigit
	isgraph
	islower
	isprint
	ispunct
	isspace
	isupper
	isxdigit
	kill
	labs
	lchown
	ldexp
	ldiv
	link
	localeconv
	localtime
	log
	log10
	longjmp
	lseek
	malloc
	mblen
	mbstowcs
	mbtowc
	memchr
	memcmp
	memcpy
	memmove
	memset
	mkdir
	mkfifo
	mktime
	modf
	nice
	offsetof
	open
	opendir
	pathconf
	pause
	perror
	pipe
	pow
	printf
	putc
	putchar
	puts
	qsort
	raise
	rand
	read
	readdir
	realloc
	remove
	rename
	rewind
	rewinddir
	rmdir
	scanf
	setgid
	setjmp
	setlocale
	setpgid
	setsid
	setuid
	sigaction
	siglongjmp
	sigpending
	sigprocmask
	sigsetjmp
	sigsuspend
	sin
	sinh
	sleep
	sprintf
	sqrt
	srand
	sscanf
	stat
	strcat
	strchr
	strcmp
	strcoll
	strcpy
	strcspn
	strerror
	strftime
	strlen
	strncat
	strncmp
	strncpy
	strpbrk
	strrchr
	strspn
	strstr
	strtod
	strtok
	strtol
	strtoul
	strxfrm
	sysconf
	system
	tan
	tanh
	tcdrain
	tcflow
	tcflush
	tcgetpgrp
	tcsendbreak
	tcsetpgrp
	time
	times
	tmpfile
	tmpnam
	tolower
	toupper
	ttyname
	tzname
	tzset
	umask
	uname
	ungetc
	unlink
	utime
	vfprintf
	vprintf
	vsprintf
	wait
	waitpid
	wcstombs
	wctomb
	write
re
	regnames_count
	regnames_count
	regname
	regmust
	regexp_pattern
	is_regexp
Devel::GlobalDestruction
	in_global_destruction
Test::More
	ok
	is
	isnt
	like
	unlike
	cmp_ok
	can_ok
	isa_ok
	new_ok
	subtest
	pass
	fail
	use_ok
	require_ok
	is_deeply
	diag
	note
	explain
	eq_array
	eq_hash
	eq_set
Test::Most
	ok
	is
	isnt
	like
	unlike
	cmp_ok
	can_ok
	isa_ok
	new_ok
	subtest
	pass
	fail
	use_ok
	require_ok
	is_deeply
	diag
	note
	explain
	eq_array
	eq_hash
	eq_set
