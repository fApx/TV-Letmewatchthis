package TV::Letmewatchthis;

=head1 NAME

TV::Letmewatchthis - Access TV Shows from Letmewatchthis

=head1 DESCRIPTION

This module downloads TV Shows from Letmewatchthis

=cut

use warnings;
use strict;
use LWP;
use HTTP::Cookies;
use HTTP::Request;
use File::Temp qw/tempfile/;
use Data::Dumper;
use File::Slurp qw/read_file/;
use File::Path qw/make_path/;
use POSIX qw/strftime/;
use File::Glob ':glob';

our $VERSION = '0.01';

use constant {
    BASE_URL      => 'http://www.primewire.ag',
    USER_AGENT    => 'User-Agent:Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.17 (KHTML, like Gecko) Chrome/24.0.1312.56',
    CACHE_FILE    => '/tmp/letmewatchthis.cache',
    YOUTUBEDL     => './youtube-dl',
};
use constant URL_TV_SEARCH_VIEWS => BASE_URL.'/?search_section=2&sort=views';
use constant URL_TV_SEARCH_SHOWS => BASE_URL.'/index.php?search_section=2&search_keywords=';

my $verbose = 0;
my $youtube_dl_updated = 0;

################################################################################

=head1 METHODS

=head2 new

    new($options)

create new TV::Letmewatchthis instance

=cut
sub new {
    my($class, %options) = @_;
    my $self = {
        _cache  => {},
        verbose => 0,
    };
    for my $key (keys %options) {
        $self->{$key} = $options{$key};
    }
    $verbose = $self->{'verbose'};
    bless $self, $class;
    $self->_init_cache();
    return $self;
}

################################################################################
# store cache on exit
sub DESTROY {
    my($self) = @_;
    $self->_store_cache();
    return;
}

################################################################################

=head2 get_tv_shows

    get_tv_shows([$title])

returns list of tv shows

=cut
sub get_tv_shows {
    my($self, $title) = @_;

    if($title) {
        #return $self->{'_cache'}->{'tv_shows_'.$title} if $self->{'_cache'}->{'tv_shows_'.$title};
        my $page = $self->_get_url(URL_TV_SEARCH_SHOWS.$title);
        $self->{'_cache'}->{'tv_shows_'.$title} = $self->_parse_tv_search($page);
        return $self->{'_cache'}->{'tv_shows_'.$title};
    }

    return $self->{'_cache'}->{'tv_shows'} if $self->{'_cache'}->{'tv_shows'};
    my $page = $self->_get_url(URL_TV_SEARCH_VIEWS);
    $self->{'_cache'}->{'tv_shows'} = $self->_parse_tv_search($page);
    return $self->{'_cache'}->{'tv_shows'};
}

################################################################################

=head2 get_tv_episodes

    get_tv_episodes($titel)

returns list of tv episodes for this title

=cut
sub get_tv_episodes {
    my($self, $title) = @_;
    return $self->{'_cache'}->{'tv_episodes'}->{$title} if $self->{'_cache'}->{'tv_episodes'}->{$title};

    my $show = $self->_get_tv_show($title);
    die('no such tv show') unless $show;
    my $episodes = [];

    my $url  = BASE_URL.$show->{'url'};
    my $page = $self->_get_url($url);
    $self->{'_cache'}->{'tv_episodes'} = $self->_parse_tv_episodes($page, $title, $self->{'_cache'}->{'tv_episodes'});
    return $self->{'_cache'}->{'tv_episodes'}->{$title};
}

################################################################################

=head2 download_tv_episodes

    download_tv_episodes($titel)

downloads tv episodes for this title

=cut
sub download_tv_episodes {
    my($self, $title) = @_;
    my $episodes = $self->get_tv_episodes($title);
    for my $season ( sort {$a<=>$b} keys %{$episodes}) {
        for my $nr ( sort {$a<=>$b} keys %{$episodes->{$season}}) {
            _out(sprintf("checking %s S%02dE%02d", $title, $season, $nr));
            $self->download_tv_episode($title, $season, $nr);
        }
    }
}

################################################################################

=head2 download_tv_season

    download_tv_season($titel, $season)

downloads tv episodes for this title and season

=cut
sub download_tv_season {
    my($self, $title, $season) = @_;
    my $episodes = $self->get_tv_episodes($title);
    if($season eq 'latest' || $season eq 'last') {
        $season = $self->_get_latest_season($episodes);
        _out(sprintf("latest season for %s is %02d", $title, $season)) if $verbose;
    }
    for my $nr ( sort {$a<=>$b} keys %{$episodes->{$season}}) {
        _out(sprintf("checking %s S%02dE%02d", $title, $season, $nr)) if $verbose;
        $self->download_tv_episode($title, $season, $nr);
    }
}

################################################################################

=head2 download_tv_episode

    download_tv_episode($title, $season, $episode)

returns tv episode

=cut
sub download_tv_episode {
    my($self, $title, $season, $nr) = @_;

    if($season eq 'latest' || $season eq 'last') {
        my $episodes = $self->get_tv_episodes($title);
        $season = $self->_get_latest_season($episodes);
    }
    if($nr eq 'latest' || $nr eq 'last') {
        $nr = $self->_get_latest_episode($title, $season);
    }

    my $file;
    my $filename = sprintf('data/%s/Season %s/S%02dE%02d', $title, $season, $season, $nr);
    my @files = bsd_glob($filename.'.*');
    @files = grep(!/\.part$/, @files);
    if(scalar @files > 0) {
        _out(sprintf("skipping already downloaded %s", $files[0])) if $verbose;
        return($files[0]);
    }
    my $urls = $self->_get_tv_episode_urls($title, $season, $nr);
    for my $url (sort { $b->{'views'} <=> $a->{'views'} } @{$urls}) {
        next if $url->{'name'} =~ m/(Sponsor|Promo)\ Host/mx;
        $file = $self->_download_episode($url->{'url'}, $url->{'name'}, $filename);
        my @files = bsd_glob($filename.'.*');
        @files = grep(!/\.part$/, @files);
        if(scalar @files > 0) {
            _out(sprintf("successfully downloaded %s", $files[0]));
            return($files[0]);
        }
    }
    return();
}

################################################################################
# INTERNAL SUBs
################################################################################
sub _get_useragent {
    my($self) = @_;

    # return cached user agent if already exists
    return $self->{'_ua'} if $self->{'_ua'};

    # create LWP object
    my $ua  = LWP::UserAgent->new(
                    keep_alive              => 1,
                    max_redirect            => 7,
                    requests_redirectable   => ['GET', 'HEAD', 'POST'],
    );

    # store cookies in a tmp file
    my($fh, $cookietempfilename) = tempfile(undef, UNLINK => 1);
    unlink($cookietempfilename);
    $ua->cookie_jar(HTTP::Cookies->new(
                                        file     => $cookietempfilename,
                                        autosave => 1,
                                    ));

    # set useragent
    $ua->agent(USER_AGENT);

    # load proxy from env
    $ua->env_proxy();

    $self->{'_ua'} = $ua;

    return $self->{'_ua'};
}

################################################################################
sub _get_url {
    my($self, $url, $method) = @_;
    # shortcut to get urls from local files
    if(-e $url) {
        print STDERR 'reading '.$url." locally\n";
        return read_file($url);
    }
    $method = 'GET' unless defined $method;
    my $request  = new HTTP::Request( $method, $url );
    my $response = $self->_get_useragent->request($request);
    if($response->is_success()) {
        return($response->as_string());
    }
    die('request '.$url.' failed: '.Dumper($response));
}

################################################################################
sub _get_url_post {
    my($self, $url) = @_;
    return $self->_get_url($url, 'POST');
}

################################################################################
sub _get_tv_show {
    my($self, $title) = @_;
    my $shows = $self->get_tv_shows($title);
    for my $show (@{$shows}) {
        if($show->{'title'} eq $title) {
            return $show;
        }
    }
    return;
}

################################################################################
sub _get_tv_episode {
    my($self, $title, $season, $episode) = @_;
    my $episodes = $self->get_tv_episodes($title);
    return unless defined $episodes->{$season};
    return unless defined $episodes->{$season}->{$episode};
    return $episodes->{$season}->{$episode};
}

################################################################################
sub _init_cache {
    my($self) = @_;
    my $cache = {};
    if(-e CACHE_FILE) {
        my $content = read_file(CACHE_FILE);
        our $VAR1;
        ## no critic
        eval $content;
        ## use critic
        die($@) if $@;
        $self->{'_cache'} = $VAR1;
    }
    return;
}

################################################################################
sub _store_cache {
    my($self, $data) = @_;
    open(my $fh, '>', CACHE_FILE) or do {
        print STDERR 'could not write cache file '.CACHE_FILE.': '.$!;
        return;
    };
    print $fh Dumper($self->{'_cache'});
    close($fh);
    return;
}
################################################################################
sub _parse_tv_search {
    my($self, $page) = @_;

    my $shows = [];
    my @matches = $page =~ m|<a\s+href="(/watch-[^"]+)"\s+title="([^"]+)\s+\((\d+)\)">|gmx;
    for my $nr (1..(@matches/3)) {
        my($url)   = shift @matches;
        my($title) = shift @matches;
        my($year)  = shift @matches;
        $title     =~ s/^Watch\s+//gmx;
        push @{$shows}, {
            'title' => $title,
            'url'   => $url,
            'year'  => $year,
        };
    }
    return $shows;
}

################################################################################
sub _parse_tv_episodes {
    my($self, $page, $title, $cache) = @_;
    $cache = {} unless defined $cache;
    my @matches = $page =~ m|<a\s+href="(/[^"]+)">E(\d+)\s+<span\s+class="tv_episode_name">\s+\-\s+([^<]+)</span>|gmx;
    for my $nr (1..(@matches/3)) {
        my($url)    = shift @matches;
        my($nr)     = shift @matches;
        my($name)   = shift @matches;
        if($url =~ m|season\-(\d+)\-episode\-(\d+)|gmx) {
            my $episode = {
                'title'     => $name,
                'url'       => $url,
                'episode'   => $2,
                'season'    => $1,
            };
            $cache->{$title}->{$1}->{$2} = $episode;
        }
    }
    return $cache;
}

################################################################################
sub _parse_tv_episode {
    my($self, $page) = @_;
    my @matches = $page =~ m|<span\s+class="movie_version_link">.*?
                             <a\s+href="([^"]+)".*?
                             .*?document\.writeln\('([^']+)'\);<.*?
                             .*?>\s*(\d+)\s+views<
                            |gmxs;
    my $urls = [];
    for my $nr (1..(@matches/3)) {
        my($url)    = shift @matches;
        my($name)   = shift @matches;
        my($views)  = shift @matches;
        next if $url !~ m|^/|gmx;
        chomp($url);
        push @{$urls}, {
            'url'   => $url,
            'name'  => $name,
            'views' => $views,
        };
    }
    return $urls;
}

################################################################################
sub _download_episode {
    my($self, $url, $provider, $filename) = @_;
    my @files = bsd_glob($filename.'*');
    @files = grep(!/\.part$/, @files);
    # already downloaded
    return $files[0] if ($files[0] && -e $files[0]);
    my @folders    = split(/\//mx, $filename);
    my $fileprefix = pop(@folders);
    make_path(join('/', @folders));
    my $download_url = $self->_expand_external_url($url);
    return unless $download_url;
    if(!$youtube_dl_updated) {
        _out("updating youtube-dl") if $verbose;
        system(YOUTUBEDL, '-U');
        $youtube_dl_updated = 1;
    }
    print system(YOUTUBEDL, $download_url, '-o', $filename.".%(ext)s");
    my $rc = $?;
    if($rc != 0 && $rc != 256) {
        _out("youtube-dl exited non-zero");
        exit;
    }
    return;
}

################################################################################
sub _get_tv_episode_urls {
    my($self, $title, $season, $nr) = @_;
    my $episode = $self->_get_tv_episode($title, $season, $nr);
    die('no such episode') unless $episode;
    my $url  = BASE_URL.$episode->{'url'};
    my $page = $self->_get_url($url);
    my $urls = $self->_parse_tv_episode($page);
    return $urls;
}

################################################################################
sub _expand_external_url {
    my($self, $url) = @_;
    $url     = BASE_URL.$url;
    my $page = $self->_get_url($url);
    my $download;
    if($page =~ m|<noframes>([^>]+)</noframes>|gmx) {
        $url  = $1;
    }
    return $url;
}

################################################################################
sub _out {
    my($txt) = @_;
    chomp($txt);
    my $date = strftime("%Y-%m-%d %H:%M:%S", localtime());
    print STDERR "[".$date."] ", $txt,"\n";
}

################################################################################
sub _get_latest_season {
    my($self, $episodes) = @_;
    my @season_nrs = (sort {$b<=>$a} keys %{$episodes});
    return if scalar @season_nrs == 0;
    return $season_nrs[0];
}

################################################################################
sub _get_latest_episode {
    my($self, $title, $season) = @_;
    my $episodes = $self->get_tv_episodes($title);
    if($season eq 'latest' || $season eq 'last') {
        $season = $self->_get_latest_season($episodes);
    }
    my @episode_nrs = (sort {$b<=>$a} keys %{$episodes->{$season}});
    return if scalar @episode_nrs == 0;
    return $episode_nrs[0];
}

################################################################################

1;

=head1 REPOSITORY

    Git: http://github.com/fApx/TV-Letmewatchthis

=head1 AUTHOR

fApx, C<< <fApx at cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2015 fApx.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
