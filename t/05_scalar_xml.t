#!/usr/bin/env perl -w
use strict;
use Test;
BEGIN { plan tests => 1 }

use MP3::M3U::Parser;

my $output = '';
my $parser = MP3::M3U::Parser->new(-seconds => 'format');
   $parser->parse('test.m3u');
   $parser->export(-format  => 'xml',
                   -toscalar => \$output);

open  FILE, ">05_scalar_xml.xml" or die "I can not open file!";
print FILE $output;
close FILE;

ok(1);
exit;

__END__
