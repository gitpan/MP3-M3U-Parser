#!/usr/bin/env perl -w
use strict;
use Test::More;

# build tool runs the whole test suite on the monolithic version.
# Don't bother testing it if exists
plan skip_all => "Skipping for monolith build test" if $ENV{AUTHOR_TESTING_MONOLITH_BUILD};

eval "use Test::Pod::Coverage;1";

$@ ? plan( skip_all => "Test::Pod::Coverage required for testing pod coverage" )
   : all_pod_coverage_ok();
