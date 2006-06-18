use strict;
use Module::Build;

Module::Build->new(
   module_name => 'MP3::M3U::Parser',
   license     => 'perl',
   requires    => {
      'File::Spec'     => 0,
      'IO::File'       => 0,
      'Cwd'            => 0,
      'Text::Template' => 0,
   },
   dist_author => 'Burak Gursoy <burak@cpan.org>',
)->create_build_script;
