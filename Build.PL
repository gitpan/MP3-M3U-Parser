use strict;
use Module::Build;
use File::Spec;
use IO::File;

my $class = Module::Build->subclass(
                class => 'MBSubclass',
                code  => raw_subclass(),
            );

my $mb = $class->new(
    module_name    => 'MP3::M3U::Parser',
    license        => 'perl',
    requires       => {
        'File::Spec'     => 0,
        'IO::File'       => 0,
        'Cwd'            => 0,
        'Text::Template' => 0,
    },
    build_requires => {
        'Test::More' => '0.40',
    },
    recommends     => {},
    sign           => 0,
    dist_author    => 'Burak Gursoy <burak@cpan.org>',
    create_license => 1,
    no_index       => {
        directory => [
            'tools',
            't',
        ]
    },
    meta_merge => {
        resources => {
            repository => 'http://bitbucket.org/burak/cpan-mp3-m3u-parser/',
        },
    },
);

$mb->create_build_script;

sub raw_subclass {
    my $file = File::Spec->catfile( 'tools', 'Build.pm' );
    my $FH   = IO::File->new;
    $FH->open( $file, 'r' ) or die "Can not open($file): $!";
    my $rv = do { local $/; <$FH> };
    close $FH;
    return $rv;
}
