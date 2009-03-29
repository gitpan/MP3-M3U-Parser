#!/usr/bin/env perl -w
use strict;
use Test::More;

eval "use Test::Pod::Coverage;1";
if ( $@ ) {
   plan skip_all => "Test::Pod::Coverage required for testing pod coverage";
} else {
   all_pod_coverage_ok();
}
