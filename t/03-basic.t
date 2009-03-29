#!/usr/bin/env perl -w
use strict;
use Test::More qw(no_plan);

use MP3::M3U::Parser;

my $parser = MP3::M3U::Parser->new(-parse_path => 'asis',
                                   -seconds    => 'format',
                                   -search     => '',
                                   -overwrite  => 1,
                                   -encoding   => 'ISO-8859-9',
                                   -expformat  => 'html');
ok(ref $parser eq 'MP3::M3U::Parser');
ok($parser eq $parser->parse('test.m3u'));
my $result = $parser->result;
ok(ref $result eq 'ARRAY');
ok($parser eq $parser->export(-file => "01_basic.html"));
my %info = $parser->info;
ok(ref $info{drive} eq 'ARRAY');
ok($parser eq $parser->reset);
