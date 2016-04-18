#!/usr/bin/perl -w
# Copyright (c) 2015-2016 Daniel Gustafsson <daniel@yesql.se>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

use strict;

die $0 . " <target branch> <rerere break>\n" if (scalar(@ARGV) != 2);

my $non_rec;
my $target = $ARGV[0];
my $rerere = $ARGV[1];
my $source = qx(git rev-parse --abbrev-ref HEAD);
chomp($source);

system("git diff $rerere..HEAD > grmph_pre_$rerere-to-HEAD.diff");

open my $BKUP, '>>', 'git_gr.out' or die 'Unable to open backup file!';

# If there was a commit breakpoint to rerere until, enable rerere and
# train the current git repo on those commits with the rerere-train.sh
# git contrib script.
if (defined($rerere))
{
	my $pr = qx(git config rerere.enabled 1; rerere-train.sh ^$rerere $source);
	print $BKUP $pr;
}

# Rebase based on the $target branch and preserve merges
my $gr = qx(git rebase -p $target);
print $BKUP $gr;

# Show the diff such that it can be properly inspected before adding and
# allow the option to save it to disc
print "Inspect git diff? Y/n [n]?: ";
system("git diff") if getc(STDIN) =~ /[yY]/;
print "Save diff? Y/n [n]?: ";
system("git diff > grmph_git_diff_$rerere.diff") if getc(STDIN) =~ /[yY]/;

# git rebase with preserved merges combined with rerere auto resolves
# most of the merge conflicts otherwise carried forward, it doesn't
# however automatically add re-add the files for commit which can be
# quite cumbersome when dealing with repo-wide merges such as Makefile
# rewrites etc. Prompt for git adding them to lessen the pain.
foreach (split/[\r\n]+/, $gr)
{
	if (/Auto-merging (\S+)/)
	{
		my $filename = $1;
		print "git add $filename Y/n [n]?: ";
		system("git add $filename") if getc(STDIN) =~ /[yY]/;
		print $BKUP "git add $filename\n";
	}
}

# Also allow for easier removal of files in case the merge has done
# wholesale deletions.
foreach (`git status`)
{
	if (/deleted by us:\s+(\S+)/)
	{
		my $filename = $1;
		print "git delete $filename Y/n [n]?: ";
		system("git rm $filename") if getc(STDIN) =~ /[yY]/;
		print $BKUP "git rm $filename\n";
	}
}
# Reset rerere config if we enabled it earlier
system("git config rerere.enabled 0") if (defined($rerere));

system("git diff --staged > grmph_post_$rerere-to-HEAD.diff");
system("interdiff grmph_post_$rerere-to-HEAD.diff grmph_pre_$rerere-to-HEAD.diff > grmph_diff_$rerere-to-HEAD.diff");

if (-e "grmph_diff_$rerere-to-HEAD.diff" && -s _)
{
	print "Non-recorded changes detected, apply? Y/n [n]: ";
	system("patch -p1 < grmph_diff_$rerere-to-HEAD.diff") if getc(STDIN) =~ /[yY]/;
	print $BKUP "patch -p1 < grmph_diff_$rerere-to-HEAD.diff\n";
	$non_rec = "applied";
}
else
{
	$non_rec = "exists";
}

close $BKUP;

print <<EOT;
Rebase of $source onto $target with merge commit and merge
conflict resolutions preserved is now in progress.  Any
remaining conflicts must be fixed and added, then commit
and run "git rebase --continue" to finish the rebase.  Use
"git rebase --abort" to revert the partial rebase.
EOT

if ($non_rec eq "exists")
{
print <<EOT

Non-recorded changes (if any) in the merge can be restored
by using "patch -p1 < grmph_diff_$rerere-to-HEAD.diff"
EOT
}
__END__
