#!/usr/bin/env bash
# Checks that each `ets` code block of the given Markdown files is in one of
# the demo's documentation examples, which the demo build compiles:
#
#   check-doc-examples.sh <Markdown file>...
#
# A block matches when its lines, without indentation and blank lines, are
# consecutive lines of an example file, so a block can be a fragment of one.
set -euo pipefail

examples=demo/entry/src/main/ets/docs
perl -e '
  use strict;
  use warnings;
  my $examples = shift @ARGV;
  sub normalize {
    my @lines = grep { length } map { s/^\s+|\s+$//gr } @_;
    return join("\n", "", @lines, "");
  }
  my @sources;
  for my $file (glob "$examples/*.ets") {
    open my $in, "<", $file or die "$file: $!";
    push @sources, normalize(<$in>);
  }
  my $failed = 0;
  for my $file (@ARGV) {
    open my $in, "<", $file or die "$file: $!";
    my ($block, $start);
    while (my $line = <$in>) {
      if (!defined $block && $line =~ /^```ets\s*$/) {
        ($block, $start) = ([], $.);
      } elsif (defined $block && $line =~ /^```\s*$/) {
        my $text = normalize(@$block);
        if (!grep { index($_, $text) >= 0 } @sources) {
          print STDERR "$file:$start: this ets block is in no file of $examples\n";
          $failed = 1;
        }
        undef $block;
      } elsif (defined $block) {
        push @$block, $line;
      }
    }
  }
  exit $failed;
' "$examples" "$@"
