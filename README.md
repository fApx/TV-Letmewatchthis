# NAME

    letmewatchthis - Fetch stream files

# OPTIONS

    Usage: letmewatchthis [options]

         Options:
         -h, --help                    Show this help message and exit
         -v, --verbose                 Print verbose output
         -V, --version                 Print version

         -S, --shows                   List tv-shows
         -d, --download                Download mode

         -t, --title <tvshow>          Select this tvshow
         -s, --season <season>         Download given season, use 'latest' to
                                       fetch last season
         -e, --episode <episode>       Download given episode only, must set
                                       season to use

# EXAMPLES

       list top tv shows

           ./letmewatchthis -S

       search tv shows

           ./letmewatchthis -S <searchstring>

       list episodes:

           ./letmewatchthis 'Suits'

       download complete last season:

           ./letmewatchthis -d 'Suits' latest

       download latest episode from latest season:

           ./letmewatchthis -d 'Suits' latest latest

       download very first episode:

           ./letmewatchthis -d 'Suits' 1 1
