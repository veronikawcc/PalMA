#!/usr/bin/env perl

use strict;
use warnings;

=head1 NAME

find-untranslated.pl - Find untranslated strings in .po files and output translation statistics

=head1 SYNOPSIS

    find-untranslated.pl [--color] [--markdown] [locale...]

=head1 DESCRIPTION

This script parses .po files and generates statistics about translation status.

It can be used in the shell to track progress, as part of a git hook or to generate
more elaborate statistics as a Markdown document.

=head1 OPTIONS

=over 12

=item C<--color>

Print the percentage of a translation in color in the shell, using L<Term::ANSIColor>.

=item C<--markdown>

Output a full report of translation status and translation contributors (based on Git commits) in
Markdown syntax, to be published in systems like Github or Jekyll.

=head1 AUTHOR

Konstantin Baierer - L<http://github.com/kba>

=head1 LICENSE AND COPYRIGHT

(c) 2016 Mannheim University Library.

Released under the MIT license.

=cut

use Term::ANSIColor;
use Data::Dumper;
use Carp qw(croak);

my $LOCALEDIR=$ENV{LOCALEDIR} || 'locale';
my %flags = map {($_=>1)} grep { /^-/smx } @ARGV;
if ($flags{'-h'} || $flags{'--help'}) {
    printf "Usage: $0 [--color] [--markdown] [locales...]\n";
    printf "\n";
    printf "Options:\n";
    printf "  --color     Colorize percentages\n";
    printf "  --markdown  Produce extensive Markdown-formatted output\n";
    exit 0;
}
my @locales = grep { ! /^-/smx } @ARGV;
unless (scalar @locales) {
    opendir my $dh, $LOCALEDIR or croak "No such directory: $LOCALEDIR";
    @locales = map { /([^\.]+)/smx } grep { !/^\./smx } readdir($dh);
    close $dh;
}

sub po_file {
    my ($locale) =  @_;
    return sprintf("%s/%s.UTF-8/LC_MESSAGES/palma.po", $LOCALEDIR, $locale);
}

sub parse_po {
    my ($locale) =  @_;
    my $fname = po_file($locale);
    open my $fh, '<', $fname or croak "No such file $fname";
    my @lines = do { <$fh>; };
    close $fh;
    my ($cur, %ret);
    my $state_msgid = 1;
    for (@lines) {
        if (/^msgid\s+"(.*)"/sxm) {
            $state_msgid = 1;
            $cur = $1;
            $ret{$cur} = q[];
        } elsif (/^msgstr\s+"(.*)"/smx) {
            $state_msgid = 0;
            $ret{$cur} .= $1;
        } elsif (/^"(.*)"/smx) {
            if ($state_msgid) {
                $cur .= $1;
            } else {
                $ret{$cur} .= $1;
            }
        }
    }
    delete $ret{q[]};
    return %ret;
}
sub percent {
    my ($ratio) = @_;
    my $perc = sprintf("%.2f", 100 * $ratio);
    return $perc unless $flags{'--color'};
    return colored($perc,
        $perc == 100 ? 'bold green' :
        $perc > 90 ? 'green' :
        $perc > 50 ? 'yellow' :
        'red');
}

my %reference_po = parse_po('en_US');
my $markdown_mode = exists $flags{'--markdown'};
my $md_header = <<'EOHEADER';
# Translation Stats

> **DO NOT EDIT!**
>
> This file is generated by `$0 --markdown`
EOHEADER
my $md_table = "|Locale|Completion|\n|---|---|";
my $md_body = q[];
for my $locale (sort @locales) {
    next if $locale eq 'en_US';
    my %po = parse_po($locale);
    my @total = keys %po;
    my @untranslated = grep { $po{$_} =~ /^$/smx || exists $reference_po{$po{$_}} } @total;
    my $nr_translated = scalar @total - scalar @untranslated;
    if (! $markdown_mode) {
        printf("%s\t%s%%\t (%s / %s)\n", $locale, percent($nr_translated / scalar @total), $nr_translated, scalar @total);
        next;
    }
    $md_table .= sprintf "\n|[%s](#%s)|%s|", $locale, lc $locale, percent($nr_translated / scalar @total);
    $md_body .= sprintf "\n## %s\n\n", $locale;
    $md_body .= sprintf "Completion: **%s** (%s / %s strings)\n\n", percent($nr_translated / scalar @total), $nr_translated, scalar @total;
    $md_body .= sprintf "Contributors:\n\n";
    my $contrib_cmd = join q[ ], 'git log --format=format:"%aN"', po_file($locale);
    ## no critic (ProhibitBacktickOperators)
    $md_body .= qx($contrib_cmd|sort|uniq|sed 's/^/  * /g');
    ## use critic
    if (scalar @untranslated) {
        $md_body .= sprintf "\nMissing:\n";
        for (sort @untranslated) {
            $md_body .= sprintf("  * `%s`\n", $_)
        }
    }
}
if ($markdown_mode) {
    print join("\n", $md_header, $md_table, $md_body);
}