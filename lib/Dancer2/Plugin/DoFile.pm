package Dancer2::Plugin::DoFile;
$Dancer2::Plugin::DoFile::VERSION = '0.0';

use strict;
use warnings;

use Dancer2::Plugin;

use JSON;

has page_loc => (
    is      => 'rw',
    default => sub {'dofiles/pages'},
);

has component_loc => (
    is      => 'rw',
    default => sub {'dofiles/components'},
);

has default_file => (
    is      => 'rw',
    default => sub {'index'},
);

plugin_keywords 'dofile';

sub BUILD {
    my $self     = shift;
    my $settings = $self->config;

    $settings->{$_} and $self->$_( $settings->{$_} )
      for qw/ page_loc component_loc default_file /;
}

sub dofile {
  my $plugin = shift;
  my $arg = shift;
  my %opts = @_;

  my $app = $plugin->app;
  my $settings = $app->settings;
  my $method = $app->request->method;
  my $pageroot = $settings->{appdir} . $plugin->page_loc;
  my $path = $arg || $app->request->path;

  # This is the specific file order we'll check

  # If any one of these returns content then we stop processing any more of them
  # Content is defined as an array ref (it's an Obj2HTML array), a hashref with a "content" element, or a scalar (assumed HTML string - it's not checked!)
  # This can lead to some interesting results if someone doesn't explicitly return undef when they want to fall through to the next file
  # as perl will return the last evaluated value, which would be intepretted as content according to the above rules
  my @filesearch = (".do", "-$method.do", ".po", "-$method.po");

  # Safety first...
  $path =~ s|/$|"/".$plugin->default_file|e;
  $path =~ s|^/+||;
  $path =~ s|\.\./||g;
  $path =~ s|~||g;

  if (!$path) { $path = $plugin->default_file; }
  if (-d $pageroot."/$path") { $path .= "/".$plugin->default_file; }

  $plugin->app->log( info => "DoFile looking for $path\n");

  my $successful = 0;

  foreach my $ext (@filesearch) {
    my $cururl = $path;
    my @path = ();

    # This iterates back through the path to find the closest FILE downstream, using the rest of the url as a "path" argument
    while (!-f $pageroot."/".$cururl.$ext && $cururl =~ s/\/([^\/]*)$//) {
      if ($1) { unshift(@path, $1); }
    }

    # To do - look for appropriate js files to include

    # "Do" the file
    if ($cururl && -f $pageroot."/".$cururl.$ext) {
      our $args = { path => \@path, thisurl => $cururl, dofileplugin => $plugin };
      my $result = do($pageroot."/".$cururl.$ext);
      if ($@ || $!) { $plugin->app->log( error => "Error processing $pageroot / $cururl.$ext: $@ $!\n"); }
      if (defined $result && ref $result eq "HASH") {
        if (defined $result->{url} && !defined $result->{redirect}) {
            $path = $result->{url};
            next OUTER;
        }
        if (defined $result->{content}) {
          return $result;
        }
        # Move on to the next file

      } elsif (ref $result eq "ARRAY") {
        return { content => $result };

      } elsif (!ref $result && $result) {
        # do we assume this is HTML? Or a file to use in templating? Who knows!
        return { content => $result };

      }
    }
  }
  # If we got here we didn't find a do file that returned some content
  return { status => 404 };
}

sub view_pathname {
  my ( $self, $view ) = @_;
  return path($view);
}
sub layout_pathname {
  my ( $self, $layout ) = @_;
  return $layout;
}

1;
