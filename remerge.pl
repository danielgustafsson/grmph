#!/usr/bin/perl

use strict;
use File::Path qw/make_path/;
use File::Copy qw/copy/;
use Getopt::Long qw/GetOptions/;
use IPC::Open3;
use Symbol qw/gensym/;

my @commits = ();
my %rebase;
my %commitcount;
my @cherry = ();
my @diff_create = ();
my @diff_modify = ();
my @diff_delete = ();

my $cmd_log;
my $merge_tree;
my $source_tree;
my $rebase_list;
my $merge_list;
my $output_dir = '/tmp/remerge/';

sub _find_in_branch
{
	my ($commit, $target) = @_;

	my @branch = qx(cd $source_tree && git branch -r --list $target --contains $commit --);
	return undef if (!@branch || scalar(@branch) == 0);
	return "  $target\n" eq $branch[0];
}

sub GitDeleteFromIndex
{
	my (@files) = @_;

	return if (scalar(@files) == 0);
	my $cmd = "cd $merge_tree && git rm --quiet -f " . join(" ", @files);
	print $cmd_log $cmd . "\n";
	return (system($cmd) == 0);
}

sub GitAddToIndex
{
	my (@files) = @_;

	return if (scalar(@files) == 0);
	my $cmd = "cd $merge_tree && git add " . join(" ", @files);
	print $cmd_log $cmd . "\n";
	return (system($cmd) == 0);
}

sub IsFromMaster
{
	return _find_in_branch(shift, "origin/master");
}

sub IsFromUpstream
{
	return _find_in_branch(shift, "upstream/REL8_3_STABLE");
}

sub IsConflictResolution
{
	return (system("cd $source_tree && git show " . shift . " | grep -q \"<<<<<<< HEAD\"") == 0);
}

sub ParseRebaseFile
{
	my ($filename) = @_;

	open(my $fh, '<', $filename) or die;

	while (<$fh>)
	{
		# Allow blank lines and comments in the file
		next if (/^\s*(#.*)?$/);
		chomp();
		$rebase{$_} = 1;
	}

	close($fh);
}

sub ParseMergeCommitFile
{
	my ($filename, $sequence) = @_;

	open(my $fh, '<', $filename) or die;

	while (<$fh>)
	{
		# Allow blank lines and comments in the file
		next if (/^\s*(#.*)?$/);
		chomp();
		
		push @commits, {
			TYPE => 'merge',
			COMMIT => $_,
			SEQ => $sequence++,
			REBASE => 0
		};
	}
}

sub CopyFile
{
	my ($from, $to) = @_;

	print $cmd_log "copy " . $from . ' => ' . $to . "\n";
	copy($from, $to);
}

#
# Parse the specified patch file and return a hash containing the filenames of
# the files involved in the three patch processes: create, delete and modify.
#
sub ParsePatch
{
	my ($patch_file) = @_;
	my %files;

	open my $ph, "<", $patch_file || die;
	while (<$ph>)
	{
		if (/^--- (.+)$/)
		{
			$a = $1;
		}
		elsif (/^\+\+\+ (.+)$/)
		{
			$b = $1;
			die "Found B without A in parsing diff" if (!$a);

			if ($b eq '/dev/null' && $a ne '/dev/null')
			{
				push @{$files{'delete'}}, substr($a, 2);
			}
			elsif ($b ne '/dev/null' && $a eq '/dev/null')
			{
				push @{$files{'create'}}, substr($b, 2);
			}
			elsif (substr($a, 2) eq substr($b, 2))
			{
				push @{$files{'modify'}}, substr($a, 2);
			}
			else
			{
				die "Error in parsing a:$a; b:$b\n";
			}

			$a = $b = undef;
		}
	}

	close($ph);

	return %files;
}

#
# Apply a patch in the merge tree iff the whole patch can be atomically (opt
# out of saving reject files from partial application for now). If the patch
# doesn't apply then rename the file to <patchfile>.problem.patch iff the
# caller specified the $rename parameter
#
sub ApplyPatch
{
	my ($patch_file, $reverse, $rename) = @_;

	my $r = ($reverse == 1 ? '--reverse' : '');
	my %errors;

	my $pid = open3(gensym, ">&STDERR", \*PH, "cd $merge_tree && git apply $r --whitespace=nowarn $patch_file");
	while (<PH>)
	{
		if ((/^error: (.+): patch does not apply$/) || (/^error: patch failed: (.+):\d+$/))
		{
			$errors{$1} = 1;
		}
	}
	waitpid($pid, 0);

	if (scalar(keys %errors))
	{
		rename $patch_file, $patch_file . '.problem.patch' if ($rename);
	}

	# Remove duplicate entries from the resulting array
	return keys(%errors);
}

sub Usage
{
	print " --output=DIR       Save patches into DIR (default: /tmp/remerge/)\n" .
		  " --mergetree=DIR    Path to the Git tree where the merge will take place\n" .
		  " --sourcetree=DIR   Path to the Git tree where the source of the merge is\n" .
	      " --rebase=FILE      File with list of patches for manual rebase\n" .
		  " --merge=FILE       File with list of merge commits making up the remerge merge\n" .
		  " --help             This screen\n";
	exit 0;
}


# Main
if (1)
{
	GetOptions(
		"output" => \$output_dir,
		"mergetree=s" => \$merge_tree,
		"sourcetree=s" => \$source_tree,
		"rebase=s" => \$rebase_list,
		"merge=s" => \$merge_list,
		"help" => sub { Usage() },
	);

	open $cmd_log, ">", "g2_command_log.txt" || die;

	# Ensure we have two trees to work with and that they are suffixed with a
	# trailing slash to avoid having to explicitly do that all the time..
	die "Error: a merge tree must be specified\n" unless ($merge_tree);
	die "Error: a source tree must be specified\n" unless ($source_tree);
	$merge_tree .= '/' unless ($merge_tree =~ /\/$/);
	$source_tree .= '/' unless ($source_tree =~ /\/$/);

	ParseRebaseFile($rebase_list) unless (!$rebase_list);
	ParseMergeCommitFile($merge_list, 1) unless (!$merge_list);

	print "XXX:\n\t$merge_tree\n\t$source_tree\n";
	exit 1;

	print "* Setting up workspace..\n";
	make_path($output_dir . '/patches/conflict') || die;
	make_path($output_dir . '/patches/mergefix') || die;
	make_path($output_dir . '/patches/rebase') || die;

	# Extract the set of commits that are contained in the merge but which are
	# not in the target branch and categorize them based on where they came
	# from and what they contain.
	print "* Extracting diff with master..\n";
	@cherry = qx(cd $source_tree && git cherry origin/master);

	print "* Identifying commits..\n";
	for (my $i = 0; $i < scalar(@cherry); $i++)
	{
		if ($cherry[$i] =~ /^\+ ([0-9a-f]+)$/)
		{
			my $type = undef;
			my $commit = $1;

			if (IsFromUpstream($commit))
			{
				$type = 'upstream';
			}
			elsif (IsConflictResolution($commit))
			{
				$type = 'conflict';
			}
			# This should clerly not happen since we are reading a list of
			# commits which is the difference from master, but just in case
			# let's ensure we don't have any errors here. 
			elsif (IsFromMaster($commit))
			{
				$type = 'master';
			}
			else
			{
				$type = 'mergefix';
			}

			$commitcount{$type}++;
			push @commits, {
					TYPE => $type,
					COMMIT => $commit,
					SEQ => $i,
					REBASE => ($rebase{$commit} ? 1 : 0)
			};
		}
	}

	# Assert that we don't have commits that we really shouldn't have at this
	# stage.
	if ($commitcount{'master'} && $commitcount{'master'} > 0)
	{
		die "Error: origin/master commits found in diff with master\n";
	}

	# Any files which were immediately deleted when the merge was initiated
	# should be removed now as well to put the tree in the same state as when
	# hacking started.
	print "* Purging deleted files from merge index..\n";
	my @file_status = qx(cd $merge_tree && git status);
	for (@file_status)
	{
		if (/^\tdeleted by (us|them):\s+(.+)$/)
		{
			GitDeleteFromIndex($2);
			$commitcount{'deletedinmerge'}++;
		}
	}

	# For each commit that make up the merge, generate the patch into a set of
	# sorted output directories with the internal order maintained in the file
	# name Commits from either upstream are discarded.
	print "* Generating patches..\n";
	for (my $i = 0; $i < scalar(@commits); $i++)
	{
		next if ($commits[$i]{TYPE} eq 'upstream' || $commits[$i]{TYPE} eq 'master');
		# "git format-patch" doesn't work for merge commits so if we have any
		# merges then fall back on extracting the patch with "git show"
		if ($commits[$i]{TYPE} eq 'merge')
		{
			system("cd $source_tree && git show $commits[$i]{COMMIT} > $output_dir/patches/conflict/0000-merge-$commits[$i]{COMMIT}.patch");
		}
		else
		{
			my $patchdir = $output_dir . "/patches/" . ($commits[$i]{REBASE} ? 'rebase' : $commits[$i]{TYPE});
			system("cd $source_tree && git format-patch -q -o $patchdir -1 --start-number=$commits[$i]{SEQ} --no-cover-letter $commits[$i]{COMMIT}");
		}
	}

	# By parsing the generated patches we build a list of operations that are
	# required in order to replay the merge
	print "* Building filelist from patches..\n";
	for my $dirname (("/patches/conflict/", "/patches/mergefix/"))
	{
		opendir my $dir, ($output_dir . $dirname);
		my @patchfiles = readdir($dir);
		closedir($dir);
		for my $patch (@patchfiles)
		{
			next if ($patch =~ /^\./);

			print $cmd_log "Parsing patch " . $dirname . $patch . "\n";
			my %diff = ParsePatch($output_dir . $dirname . $patch);
			next if (scalar(keys(%diff)) == 0);
			push @diff_create, @{$diff{'create'}} if ($diff{'create'});
			push @diff_modify, @{$diff{'modify'}} if ($diff{'modify'});
			push @diff_delete, @{$diff{'delete'}} if ($diff{'delete'});
		}
	}

	# At this point we have a list of files that have been added, changed or
	# removed as part of the merge. Reapplying the patches that led up to the
	# current state of the files, only to discard the commit history that the
	# patches make up, is equal to just copying the files across the filesystem
	# so let's do that instead.

	# Generate a hash of the deleted files. If a file was subsequently removed
	# after touched in a diff then it should be excluded from the file copying
	# operations so make that easy to look up.
	my %delete_lookup = map { $_, 1 } @diff_delete;

	print "* Reapplying files from merge to new mergetree..\n";
	for ((@diff_create, @diff_modify))
	{
		next if $delete_lookup{$_};

		CopyFile($source_tree . $_, $merge_tree . $_);
		GitAddToIndex($_);
	}
	for (@diff_delete)
	{
		GitDeleteFromIndex($_);
	}

	# The commits in the rebase file should be excluded from the final replay
	# such that they can be reapplied manually once the merge is committed.
	# This allows for pulling out fixes that aren't conflict resolutions and
	# committing them separately to make the VCS log properly readable for
	# future code forensics.
	print "* Reverse applying the excluded patches from the rebase list..\n";

	opendir my $dir, ($output_dir . "/patches/rebase");
	my @patchfiles = readdir($dir);
	closedir($dir);
	for my $patch (@patchfiles)
	{
		next if ($patch =~ /^\./);

		my @errors = ApplyPatch($output_dir . "/patches/rebase/" . $patch, 1, 1);
		if (scalar(@errors) == 0)
		{
			my %diff = ParsePatch($output_dir . "/patches/rebase/" . $patch);
			GitAddToIndex(@{$diff{'create'}}) if ($diff{'create'});
			GitAddToIndex(@{$diff{'modify'}}) if ($diff{'modify'});
			GitDeleteFromIndex(@{$diff{'delete'}}) if ($diff{'delete'});
		}
		else
		{
			print "* Error: rebase patch " . $patch . " failed to apply: " . @errors . "\n";
		}
	}

	print "= " . scalar(@cherry) . " commits of which:\n";
	print "\tconflict resolutions       : " . $commitcount{'conflict'} . "\n";
	print "\tmerge fixes                : " . $commitcount{'mergefix'} . "\n";
	print "\tupstream commits           : " . $commitcount{'upstream'} . "\n";
	print "\tcopied files               : " . (scalar(@diff_create) + scalar(@diff_modify)) . "\n";
	print "\tdeleted files              : " . (scalar(@diff_delete) + $commitcount{'deletedinmerge'}) . "\n";

	close($cmd_log);
}

__END__
