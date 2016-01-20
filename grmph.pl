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

die $0 . " <target branch> [rerere break]\n" if (!scalar(@ARGV) || scalar(@ARGV) > 2);

print "Have you extracted a diff of any changes outside the conflict resolutions? Y/n [n] ";
exit 0 if getc(STDIN) !~ /[yY]/;

my $target = $ARGV[0];
my $source = qx(git rev-parse --abbrev-ref HEAD);
chomp($source);
my $rerere = $ARGV[1] if (scalar(@ARGV) == 2);

open my $BKUP, '>>', 'git_gr.out' or die 'Unable to open backup file!';

# If there was a commit breakpoint to rerere until, enable rerere and
# train the current git repo on those commits with the rerere-train.sh
# git contrib script.
if (defined($rerere)) {
	my $pr = qx(git config rerere.enabled 1; rerere-train.sh ^$rerere $source);
	print $BKUP $pr;
}

# Rebase based on the $target branch and preserve merges
my $gr = qx(git rebase -p $target);
print $BKUP $gr;

# Show the diff such that it can be properly inspected before adding
system("git diff");

# git rebase with preserved merges combined with rerere auto resolves
# most of the merge conflicts otherwise carried forward, it doesn't
# however automatically add re-add the files for commit which can be
# quite cumbersome when dealing with repo-wide merges such as Makefile
# rewrites etc. Prompt for git adding them to lessen the pain.
foreach (split/[\r\n]+/, $gr) {
	if (/Auto-merging (\S+)/) {
		my $filename = $1;
		print "git add $filename Y/n [n]?: ";
		system("git add $filename") if getc(STDIN) =~ /[yY]/;
		print $BKUP "git add $filename\n";
	}
}

# Reset rerere config if we enabled it earlier
system("git config rerere.enabled 0") if (defined($rerere));

close $BKUP;

print <<EOT;
Rebase of $source onto $target with merges preserved
is now in progress. Any remaining conflicts must be fixed
and added, then commit and run "git rebase --continue" to
finish the rebase
EOT
__END__
