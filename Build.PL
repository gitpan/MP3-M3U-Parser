use strict;
use lib qw( builder );
use Build;

my $mb = Build->new;
$mb->change_versions(1);
$mb->create_build_script;
