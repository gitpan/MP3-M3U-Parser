use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'MP3::M3U::Parser',
    'VERSION_FROM' => 'Parser.pm',
    'PREREQ_PM'    => { 'File::Spec'   => 0,
                        'IO::File'     => 0,
                        'Data::Dumper' => 0,},
    ($] >= 5.005 ? (
    'AUTHOR'       => 'Burak Gursoy <burak@cpan.org>',
    'ABSTRACT'     => 'Perl extension for parsing mp3 lists',
     ) : ()),
);
