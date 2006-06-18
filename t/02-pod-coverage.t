#!/usr/bin/env perl -w
use strict;
BEGIN { do 't/skip.test' or die "Can't include skip.test!" }

eval "use Test::Pod::Coverage;1";
if($@) {
   plan skip_all => "Test::Pod::Coverage required for testing pod coverage";
} else {
   plan tests => 1;
   pod_coverage_ok('MP3::M3U::Parser');
}
