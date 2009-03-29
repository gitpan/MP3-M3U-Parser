#!/usr/bin/env perl -w
use strict;
use Test::More qw(no_plan);
use MP3::M3U::Parser;

my $output = '';
my $parser = MP3::M3U::Parser->new(-seconds => 'format');
   $parser->parse('test.m3u');
   $parser->export(-format  => 'html',
                   -toscalar => \$output);

open  FILE, ">06_scalar_html.html" or die "I can not open file!";
print FILE $output;
close FILE;

ok(1);
