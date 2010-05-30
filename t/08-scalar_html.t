#!/usr/bin/env perl -w
use strict;
use warnings;
use IO::File;
use Carp       qw( croak   );
use Test::More qw( no_plan );
use File::Spec;

BEGIN {
    use_ok('MP3::M3U::Parser');
}

my $output = q{};
my $parser = MP3::M3U::Parser->new(
                -seconds => 'format'
            );
$parser->parse(
    File::Spec->catfile( qw/ t data test.m3u / )
);
$parser->export(
    -format   => 'html',
    -toscalar => \$output,
);

my $fh = IO::File->new;
$fh->open( '08_scalar_html.html', '>' ) or croak "I can not open file: $!";
print {$fh} $output or croak "Can't print to FH: $!";
$fh->close;

ok(1, 'Some test');
