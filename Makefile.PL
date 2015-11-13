use inc::Module::Install;

name       'TV-Letmewatchthis';
all_from   'lib/TV/Letmewatchthis.pm';
author     'fApx <fApx@cpan.org>';
license    'perl';
repository 'http://github.com/fApx/TV-Letmewatchthis';

requires 'LWP';
requires 'File::Slurp';
requires 'HTTP::Cookies';
requires 'HTTP::Request';

build_requires 'Test::More';

WriteAll;
